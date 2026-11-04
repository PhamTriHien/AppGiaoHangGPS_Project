import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum Icon3dStyle {
  scooterExpress(
    assetPath: 'assets/icons_3d/scooter_express_3d.png',
    primaryColor: AppColors.primary,
    secondaryColor: AppColors.accent,
    glowColor: AppColors.routeRibbonFill,
    fallbackIcon: Icons.delivery_dining_rounded,
    label: '3D Express',
  ),
  parcelBox(
    assetPath: 'assets/icons_3d/parcel_box_3d.png',
    primaryColor: AppColors.primary,
    secondaryColor: AppColors.accent,
    glowColor: AppColors.success,
    fallbackIcon: Icons.inventory_2_rounded,
    label: '3D Parcel',
  ),
  gpsPinRadar(
    assetPath: 'assets/icons_3d/gps_pin_radar_3d.png',
    primaryColor: AppColors.routeRibbonFill,
    secondaryColor: AppColors.primary,
    glowColor: AppColors.accent,
    fallbackIcon: Icons.radar_rounded,
    label: '3D GPS Radar',
  ),
  walletVault(
    assetPath: 'assets/icons_3d/wallet_vault_3d.png',
    primaryColor: AppColors.success,
    secondaryColor: AppColors.primary,
    glowColor: AppColors.warning,
    fallbackIcon: Icons.account_balance_wallet_rounded,
    label: '3D Wallet',
  ),
  hub2hBatch(
    assetPath: 'assets/icons_3d/hub_2h_batch_3d.png',
    primaryColor: Color(0xFF06B6D4),
    secondaryColor: AppColors.primary,
    glowColor: Color(0xFF22D3EE),
    fallbackIcon: Icons.hub_rounded,
    label: '3D 2H Batch',
  ),
  cargoTruck(
    assetPath: 'assets/icons_3d/cargo_truck_3d.png',
    primaryColor: Color(0xFF4F46E5),
    secondaryColor: Color(0xFFF97316),
    glowColor: Color(0xFF38BDF8),
    fallbackIcon: Icons.local_shipping_rounded,
    label: '3D Cargo Truck',
  ),
  foodMarket(
    assetPath: 'assets/icons_3d/food_market_3d.png',
    primaryColor: Color(0xFFF97316),
    secondaryColor: Color(0xFFF59E0B),
    glowColor: Color(0xFFFB923C),
    fallbackIcon: Icons.restaurant_menu_rounded,
    label: '3D Food & Market',
  ),
  merchantStore(
    assetPath: 'assets/icons_3d/merchant_store_3d.png',
    primaryColor: Color(0xFFD97706),
    secondaryColor: AppColors.success,
    glowColor: Color(0xFFFBBF24),
    fallbackIcon: Icons.storefront_rounded,
    label: '3D Merchant Store',
  ),
  driverPartner(
    assetPath: 'assets/icons_3d/driver_partner_3d.png',
    primaryColor: Color(0xFF059669),
    secondaryColor: AppColors.primary,
    glowColor: Color(0xFF34D399),
    fallbackIcon: Icons.sports_motorsports_rounded,
    label: '3D Driver Partner',
  ),
  aiAssistant(
    assetPath: 'assets/icons_3d/ai_assistant_3d.png',
    primaryColor: Color(0xFF6366F1),
    secondaryColor: Color(0xFF06B6D4),
    glowColor: Color(0xFF38BDF8),
    fallbackIcon: Icons.auto_awesome_rounded,
    label: '3D AI Assistant',
  ),
  luckyWheel(
    assetPath: 'assets/icons_3d/lucky_wheel_3d.png',
    primaryColor: Color(0xFF7C3AED),
    secondaryColor: Color(0xFFF59E0B),
    glowColor: Color(0xFFFBBF24),
    fallbackIcon: Icons.casino_rounded,
    label: '3D Lucky Wheel',
  ),
  mysteryBox(
    assetPath: 'assets/icons_3d/mystery_box_3d.png',
    primaryColor: Color(0xFF6D28D9),
    secondaryColor: Color(0xFFF59E0B),
    glowColor: Color(0xFF22D3EE),
    fallbackIcon: Icons.redeem_rounded,
    label: '3D Mystery Box',
  ),
  voucherFlash(
    assetPath: 'assets/icons_3d/voucher_flash_3d.png',
    primaryColor: Color(0xFFF43F5E),
    secondaryColor: Color(0xFFF59E0B),
    glowColor: Color(0xFFFBBF24),
    fallbackIcon: Icons.bolt_rounded,
    label: '3D Flash Voucher',
  ),
  adminShieldOps(
    assetPath: 'assets/icons_3d/admin_shield_ops_3d.png',
    primaryColor: Color(0xFF087F5B),
    secondaryColor: AppColors.primary,
    glowColor: Color(0xFF34D399),
    fallbackIcon: Icons.admin_panel_settings_rounded,
    label: '3D Admin Shield',
  ),
  homePortal(
    assetPath: 'assets/icons_3d/home_portal_3d.png',
    primaryColor: AppColors.primary,
    secondaryColor: Color(0xFF10B981),
    glowColor: Color(0xFF38BDF8),
    fallbackIcon: Icons.home_rounded,
    label: '3D Home Portal',
  ),
  createPlus(
    assetPath: 'assets/icons_3d/create_plus_3d.png',
    primaryColor: Color(0xFF0EA5E9),
    secondaryColor: Color(0xFF10B981),
    glowColor: Color(0xFF6EE7B7),
    fallbackIcon: Icons.add_box_rounded,
    label: '3D Create Order',
  ),
  orderReceipt(
    assetPath: 'assets/icons_3d/order_receipt_3d.png',
    primaryColor: AppColors.primary,
    secondaryColor: Color(0xFF059669),
    glowColor: Color(0xFF34D399),
    fallbackIcon: Icons.receipt_long_rounded,
    label: '3D Order Receipt',
  ),
  addressBook(
    assetPath: 'assets/icons_3d/address_book_3d.png',
    primaryColor: Color(0xFF2563EB),
    secondaryColor: Color(0xFFF97316),
    glowColor: Color(0xFFFB923C),
    fallbackIcon: Icons.bookmarks_rounded,
    label: '3D Address Book',
  ),
  notificationBell(
    assetPath: 'assets/icons_3d/notification_bell_3d.png',
    primaryColor: Color(0xFFF59E0B),
    secondaryColor: Color(0xFFF43F5E),
    glowColor: Color(0xFFFBBF24),
    fallbackIcon: Icons.notifications_active_outlined,
    label: '3D Notification Bell',
  ),
  userProfile(
    assetPath: 'assets/icons_3d/user_profile_3d.png',
    primaryColor: AppColors.primary,
    secondaryColor: Color(0xFF10B981),
    glowColor: Color(0xFF22D3EE),
    fallbackIcon: Icons.person_rounded,
    label: '3D User Profile',
  ),
  shoppingCart(
    assetPath: 'assets/icons_3d/shopping_cart_3d.png',
    primaryColor: Color(0xFFF97316),
    secondaryColor: AppColors.primary,
    glowColor: Color(0xFF34D399),
    fallbackIcon: Icons.shopping_cart_rounded,
    label: '3D Shopping Cart',
  ),
  chatSupport(
    assetPath: 'assets/icons_3d/chat_support_3d.png',
    primaryColor: Color(0xFF10B981),
    secondaryColor: AppColors.primary,
    glowColor: Color(0xFF6EE7B7),
    fallbackIcon: Icons.forum_rounded,
    label: '3D Chat Support',
  ),
  analyticsChart(
    assetPath: 'assets/icons_3d/analytics_chart_3d.png',
    primaryColor: Color(0xFF6366F1),
    secondaryColor: Color(0xFF10B981),
    glowColor: Color(0xFFFBBF24),
    fallbackIcon: Icons.insights_rounded,
    label: '3D Analytics Chart',
  ),
  csvImport(
    assetPath: 'assets/icons_3d/csv_import_3d.png',
    primaryColor: Color(0xFF059669),
    secondaryColor: AppColors.primary,
    glowColor: Color(0xFF38BDF8),
    fallbackIcon: Icons.upload_file_rounded,
    label: '3D CSV Import',
  ),
  settingsGear(
    assetPath: 'assets/icons_3d/settings_gear_3d.png',
    primaryColor: AppColors.primary,
    secondaryColor: Color(0xFF06B6D4),
    glowColor: Color(0xFF22D3EE),
    fallbackIcon: Icons.settings_outlined,
    label: '3D Settings Gear',
  ),
  themeSunMoon(
    assetPath: 'assets/icons_3d/theme_sun_moon_3d.png',
    primaryColor: Color(0xFFF59E0B),
    secondaryColor: Color(0xFF1E40AF),
    glowColor: Color(0xFFFDE047),
    fallbackIcon: Icons.wb_sunny_rounded,
    label: '3D Theme Sun & Moon',
  );

  final String assetPath;
  final Color primaryColor;
  final Color secondaryColor;
  final Color glowColor;
  final IconData fallbackIcon;
  final String label;

  const Icon3dStyle({
    required this.assetPath,
    required this.primaryColor,
    required this.secondaryColor,
    required this.glowColor,
    required this.fallbackIcon,
    required this.label,
  });
}

class GhstAiIcon extends StatelessWidget {
  final Icon3dStyle style;
  final double size;
  final bool circular;
  final double borderRadius;
  final Color? borderColor;
  final Color? glowColor;
  final bool selected;
  final bool dimmed;
  final double imageScale;

  const GhstAiIcon({
    super.key,
    required this.style,
    this.size = 36,
    this.circular = false,
    this.borderRadius = 10,
    this.borderColor,
    this.glowColor,
    this.selected = false,
    this.dimmed = false,
    this.imageScale = 1.15,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSize = (!size.isFinite || size <= 0) ? 0.0 : size;
    if (effectiveSize == 0.0) {
      return const SizedBox.shrink();
    }
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final cachePx = (effectiveSize * dpr * 2.2).round().clamp(64, 512);
    final effectiveBorderColor =
        borderColor ??
        (selected
            ? style.primaryColor.withValues(alpha: 0.85)
            : style.primaryColor.withValues(alpha: 0.28));
    final effectiveGlow = glowColor ?? style.primaryColor;
    final radius = BorderRadius.circular(borderRadius);

    final imageStack = Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFFF6FAFF)),
        Transform.scale(
          scale: imageScale,
          filterQuality: FilterQuality.medium,
          child: Image.asset(
            style.assetPath,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            cacheWidth: cachePx,
            cacheHeight: cachePx,
            filterQuality: FilterQuality.medium,
            isAntiAlias: true,
            errorBuilder: (_, _, _) => CustomPaint(
              painter: _FallbackOrbPainter(
                primary: style.primaryColor,
                secondary: style.secondaryColor,
                glow: style.glowColor,
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.34),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.42],
              ),
            ),
          ),
        ),
      ],
    );

    Widget badge = Container(
      width: effectiveSize,
      height: effectiveSize,
      decoration: BoxDecoration(
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : radius,
        border: Border.all(
          color: effectiveBorderColor,
          width: selected ? 1.6 : 1.1,
        ),
        boxShadow: dimmed || effectiveSize < 24
            ? null
            : [
                BoxShadow(
                  color: effectiveGlow.withValues(
                    alpha: selected ? 0.30 : 0.16,
                  ),
                  blurRadius: selected ? 10 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: circular
          ? ClipOval(child: imageStack)
          : ClipRRect(
              borderRadius: BorderRadius.circular(
                math.max(0.0, borderRadius - 1.0),
              ),
              child: imageStack,
            ),
    );

    if (dimmed) {
      badge = Opacity(opacity: 0.46, child: badge);
    }
    return ExcludeSemantics(child: RepaintBoundary(child: badge));
  }
}

class Animated3dIconBadge extends StatefulWidget {
  final Icon3dStyle style;
  final double size;
  final bool showRadarPulse;
  final bool isSelected;
  final bool animateIdle;
  final bool forceContinuousInTest;
  final VoidCallback? onTap;

  const Animated3dIconBadge({
    super.key,
    required this.style,
    this.size = 76,
    this.showRadarPulse = true,
    this.isSelected = false,
    this.animateIdle = true,
    this.forceContinuousInTest = false,
    this.onTap,
  });

  @override
  State<Animated3dIconBadge> createState() => _Animated3dIconBadgeState();
}

class _Animated3dIconBadgeState extends State<Animated3dIconBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _pointerTiltX = -0.06;
  double _pointerTiltY = 0.09;
  double _targetPointerTiltX = -0.06;
  double _targetPointerTiltY = 0.09;
  double _tapImpulse = 0.0;

  bool get _isAutomatedTestBinding {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTest');
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
      value: widget.animateIdle ? 0.0 : 0.25,
    )..addListener(_decayTapImpulse);
    _startAnimationLoop();
  }

  void _decayTapImpulse() {
    if (_tapImpulse > 0.001) {
      _tapImpulse = (_tapImpulse * 0.92).clamp(0.0, 1.0);
    } else if (_tapImpulse != 0.0) {
      _tapImpulse = 0.0;
    }
    final dx = _targetPointerTiltX - _pointerTiltX;
    final dy = _targetPointerTiltY - _pointerTiltY;
    if (dx.abs() > 0.0004 || dy.abs() > 0.0004) {
      _pointerTiltX += dx * 0.16;
      _pointerTiltY += dy * 0.16;
    } else {
      _pointerTiltX = _targetPointerTiltX;
      _pointerTiltY = _targetPointerTiltY;
    }
  }

  void _startAnimationLoop() {
    if (widget.forceContinuousInTest ||
        (!_isAutomatedTestBinding && widget.animateIdle)) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else if (_isAutomatedTestBinding && widget.animateIdle) {
      _controller.forward(from: 0.0);
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      _controller.value = 0.25;
    }
  }

  @override
  void didUpdateWidget(covariant Animated3dIconBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.forceContinuousInTest != widget.forceContinuousInTest ||
        oldWidget.animateIdle != widget.animateIdle) {
      _startAnimationLoop();
    } else if ((widget.forceContinuousInTest ||
            (!_isAutomatedTestBinding && widget.animateIdle)) &&
        !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_decayTapImpulse);
    _controller.dispose();
    super.dispose();
  }

  void _updateTiltFromLocalOffset(Offset localPosition) {
    final half = widget.size / 2.0;
    if (half <= 0) return;
    final normX = ((localPosition.dx - half) / half).clamp(-1.0, 1.0);
    final normY = ((localPosition.dy - half) / half).clamp(-1.0, 1.0);
    final nextTiltY = normX * 0.24;
    final nextTiltX = -normY * 0.24;
    _targetPointerTiltY = nextTiltY;
    _targetPointerTiltX = nextTiltX;
    if (!_controller.isAnimating &&
        ((nextTiltY - _pointerTiltY).abs() > 0.004 ||
            (nextTiltX - _pointerTiltX).abs() > 0.004)) {
      setState(() {
        _pointerTiltY += (nextTiltY - _pointerTiltY) * 0.35;
        _pointerTiltX += (nextTiltX - _pointerTiltX) * 0.35;
      });
    }
  }

  void _trigger3dPulseWave() {
    setState(() {
      _tapImpulse = 1.0;
    });
    if ((_isAutomatedTestBinding && !widget.forceContinuousInTest) ||
        !widget.animateIdle) {
      _controller.forward(from: 0.0);
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveSize =
        (!widget.size.isFinite || widget.size <= 0) ? 0.0 : widget.size;
    if (effectiveSize == 0.0) {
      return const SizedBox.shrink();
    }
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final targetCachePx = (effectiveSize * dpr * 2.0).round().clamp(160, 512);
    return RepaintBoundary(
      child: MouseRegion(
        onHover: (event) => _updateTiltFromLocalOffset(event.localPosition),
        onExit: (_) {
          _targetPointerTiltX = -0.06;
          _targetPointerTiltY = 0.09;
          if (!_controller.isAnimating &&
              (_pointerTiltX != -0.06 || _pointerTiltY != 0.09)) {
            setState(() {
              _pointerTiltX = -0.06;
              _pointerTiltY = 0.09;
            });
          }
        },
        child: GestureDetector(
          onPanUpdate: (details) =>
              _updateTiltFromLocalOffset(details.localPosition),
          onTap: _trigger3dPulseWave,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final phase = _controller.value;
              final fullAngle = phase * math.pi * 2.0;

              final motion = _computePhysical3dMotion(
                style: widget.style,
                fullAngle: fullAngle,
                isSelected: widget.isSelected,
                tapImpulse: _tapImpulse,
              );

              final dynamicTiltX = _pointerTiltX + motion.pitchX;
              final dynamicTiltY = _pointerTiltY + motion.yawY;
              final impulseScale = 1.0 + _tapImpulse * 0.11;

              final transform3d = Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..translateByDouble(
                  motion.offsetX,
                  motion.offsetY - _tapImpulse * 4.0,
                  0.0,
                  1.0,
                )
                ..rotateX(dynamicTiltX)
                ..rotateY(dynamicTiltY)
                ..rotateZ(motion.rollZ)
                ..scaleByDouble(
                  motion.scale * impulseScale,
                  motion.scale * impulseScale,
                  1.0,
                  1.0,
                );

              final shadowScale = (1.0 - (motion.offsetY.abs() / 34.0)).clamp(
                0.68,
                1.05,
              );

              return SizedBox(
                width: effectiveSize,
                height: effectiveSize + 16,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _Holographic3dPedestalPainter(
                          progress: phase,
                          primaryColor: widget.style.primaryColor,
                          glowColor: widget.style.glowColor,
                          isSelected: widget.isSelected,
                          showRadarPulse: widget.showRadarPulse,
                          tiltX: dynamicTiltX,
                          tiltY: dynamicTiltY,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 1,
                      child: Transform.scale(
                        scaleX: shadowScale,
                        scaleY: shadowScale * 0.36,
                        child: Container(
                          width: effectiveSize * 0.74,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: widget.style.secondaryColor.withValues(
                                  alpha: 0.40 * shadowScale,
                                ),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Transform(
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.medium,
                      transform: transform3d,
                      child: Container(
                        width: widget.size * 0.88,
                        height: widget.size * 0.88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: widget.isSelected
                                ? widget.style.primaryColor
                                : Colors.white.withValues(alpha: 0.95),
                            width: widget.isSelected ? 2.4 : 1.7,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: widget.style.primaryColor.withValues(
                                alpha: widget.isSelected ? 0.50 : 0.30,
                              ),
                              blurRadius: widget.isSelected ? 18 : 12,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: widget.style.glowColor.withValues(
                                alpha: widget.isSelected ? 0.36 : 0.16,
                              ),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Transform.scale(
                                scale: 1.07,
                                filterQuality: FilterQuality.medium,
                                child: Image.asset(
                                  widget.style.assetPath,
                                  fit: BoxFit.cover,
                                  excludeFromSemantics: true,
                                  cacheWidth: targetCachePx,
                                  cacheHeight: targetCachePx,
                                  filterQuality: FilterQuality.medium,
                                  isAntiAlias: true,
                                  errorBuilder: (_, _, _) => CustomPaint(
                                    painter: _FallbackOrbPainter(
                                      primary: widget.style.primaryColor,
                                      secondary: widget.style.secondaryColor,
                                      glow: widget.style.glowColor,
                                    ),
                                  ),
                                ),
                              ),
                              CustomPaint(
                                painter: _Photorealistic3dVfxOverlayPainter(
                                  style: widget.style,
                                  phase: phase,
                                  tiltX: dynamicTiltX,
                                  tiltY: dynamicTiltY,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  _Physical3dMotion _computePhysical3dMotion({
    required Icon3dStyle style,
    required double fullAngle,
    required bool isSelected,
    required double tapImpulse,
  }) {
    final baseSelectLift = isSelected ? -1.8 : 0.0;
    final smoothBounce1 = 0.5 * (1.0 - math.cos(fullAngle));
    final smoothBounce2 = 0.5 * (1.0 - math.cos(fullAngle * 2.0));
    switch (style) {
      case Icon3dStyle.scooterExpress:
        return _Physical3dMotion(
          offsetX: math.sin(fullAngle) * 1.4,
          offsetY: baseSelectLift - 2.6 * smoothBounce2,
          pitchX: 0.08 * math.sin(fullAngle * 2.0),
          yawY: 0.14 * math.cos(fullAngle),
          rollZ: 0.04 * math.sin(fullAngle),
          scale: 1.0 + 0.024 * math.sin(fullAngle * 2.0),
        );
      case Icon3dStyle.parcelBox:
      case Icon3dStyle.hub2hBatch:
        return _Physical3dMotion(
          offsetX: math.sin(fullAngle) * 0.8,
          offsetY: baseSelectLift - 3.2 * math.sin(fullAngle),
          pitchX: 0.085 * math.cos(fullAngle),
          yawY: 0.14 * math.sin(fullAngle),
          rollZ: 0.024 * math.cos(fullAngle),
          scale: 1.0 + 0.022 * math.sin(fullAngle),
        );
      case Icon3dStyle.gpsPinRadar:
      case Icon3dStyle.driverPartner:
        return _Physical3dMotion(
          offsetX: 0.0,
          offsetY: baseSelectLift - 3.5 * smoothBounce1,
          pitchX: 0.095 * math.sin(fullAngle),
          yawY: 0.13 * math.cos(fullAngle),
          rollZ: 0.02 * math.sin(fullAngle),
          scale: 1.0 + 0.025 * smoothBounce1,
        );
      case Icon3dStyle.walletVault:
      case Icon3dStyle.voucherFlash:
        return _Physical3dMotion(
          offsetX: math.cos(fullAngle) * 1.0,
          offsetY: baseSelectLift - 3.0 * math.sin(fullAngle),
          pitchX: 0.085 * math.sin(fullAngle),
          yawY: 0.14 * math.cos(fullAngle),
          rollZ: 0.03 * math.sin(fullAngle),
          scale: 1.0 + 0.024 * math.cos(fullAngle),
        );
      case Icon3dStyle.cargoTruck:
        return _Physical3dMotion(
          offsetX: math.sin(fullAngle) * 1.6,
          offsetY: baseSelectLift - 2.2 * smoothBounce2,
          pitchX: 0.065 * math.sin(fullAngle * 2.0),
          yawY: 0.12 * math.cos(fullAngle),
          rollZ: 0.025 * math.sin(fullAngle),
          scale: 1.0 + 0.020 * math.sin(fullAngle * 2.0),
        );
      case Icon3dStyle.foodMarket:
      case Icon3dStyle.merchantStore:
        return _Physical3dMotion(
          offsetX: 0.0,
          offsetY: baseSelectLift - 2.9 * smoothBounce1,
          pitchX: 0.075 * math.cos(fullAngle),
          yawY: 0.125 * math.sin(fullAngle),
          rollZ: 0.02 * math.cos(fullAngle),
          scale: 1.0 + 0.022 * smoothBounce1,
        );
      case Icon3dStyle.aiAssistant:
        return _Physical3dMotion(
          offsetX: math.sin(fullAngle) * 1.2,
          offsetY: baseSelectLift - 3.8 * smoothBounce1,
          pitchX: 0.09 * math.sin(fullAngle),
          yawY: 0.15 * math.cos(fullAngle),
          rollZ: 0.035 * math.sin(fullAngle),
          scale: 1.0 + 0.028 * smoothBounce1,
        );
      case Icon3dStyle.luckyWheel:
      case Icon3dStyle.mysteryBox:
        return _Physical3dMotion(
          offsetX: math.cos(fullAngle) * 0.9,
          offsetY: baseSelectLift - 3.3 * smoothBounce1,
          pitchX: 0.08 * math.sin(fullAngle),
          yawY: 0.14 * math.cos(fullAngle),
          rollZ: 0.035 * math.cos(fullAngle),
          scale: 1.0 + 0.026 * smoothBounce1,
        );
      case Icon3dStyle.adminShieldOps:
      case Icon3dStyle.settingsGear:
        return _Physical3dMotion(
          offsetX: 0.0,
          offsetY: baseSelectLift - 3.1 * smoothBounce1,
          pitchX: 0.08 * math.cos(fullAngle),
          yawY: 0.135 * math.sin(fullAngle),
          rollZ: 0.018 * math.sin(fullAngle),
          scale: 1.0 + 0.024 * smoothBounce1,
        );
      case Icon3dStyle.homePortal:
      case Icon3dStyle.createPlus:
        return _Physical3dMotion(
          offsetX: math.sin(fullAngle) * 0.7,
          offsetY: baseSelectLift - 3.0 * smoothBounce1,
          pitchX: 0.075 * math.sin(fullAngle),
          yawY: 0.13 * math.cos(fullAngle),
          rollZ: 0.02 * math.sin(fullAngle),
          scale: 1.0 + 0.023 * smoothBounce1,
        );
      case Icon3dStyle.orderReceipt:
      case Icon3dStyle.addressBook:
      case Icon3dStyle.csvImport:
        return _Physical3dMotion(
          offsetX: math.cos(fullAngle) * 0.75,
          offsetY: baseSelectLift - 2.9 * smoothBounce1,
          pitchX: 0.08 * math.cos(fullAngle),
          yawY: 0.13 * math.sin(fullAngle),
          rollZ: 0.022 * math.cos(fullAngle),
          scale: 1.0 + 0.022 * smoothBounce1,
        );
      case Icon3dStyle.notificationBell:
      case Icon3dStyle.themeSunMoon:
        return _Physical3dMotion(
          offsetX: math.sin(fullAngle) * 0.9,
          offsetY: baseSelectLift - 3.2 * smoothBounce1,
          pitchX: 0.085 * math.sin(fullAngle),
          yawY: 0.14 * math.cos(fullAngle),
          rollZ: 0.042 * math.sin(fullAngle * 2.0),
          scale: 1.0 + 0.024 * smoothBounce1,
        );
      case Icon3dStyle.userProfile:
      case Icon3dStyle.shoppingCart:
      case Icon3dStyle.chatSupport:
      case Icon3dStyle.analyticsChart:
        return _Physical3dMotion(
          offsetX: math.sin(fullAngle) * 0.85,
          offsetY: baseSelectLift - 3.1 * smoothBounce1,
          pitchX: 0.08 * math.sin(fullAngle),
          yawY: 0.135 * math.cos(fullAngle),
          rollZ: 0.024 * math.sin(fullAngle),
          scale: 1.0 + 0.024 * smoothBounce1,
        );
    }
  }
}

class _Physical3dMotion {
  final double offsetX;
  final double offsetY;
  final double pitchX;
  final double yawY;
  final double rollZ;
  final double scale;

  const _Physical3dMotion({
    required this.offsetX,
    required this.offsetY,
    required this.pitchX,
    required this.yawY,
    required this.rollZ,
    required this.scale,
  });
}

class _Holographic3dPedestalPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color glowColor;
  final bool isSelected;
  final bool showRadarPulse;
  final double tiltX;
  final double tiltY;

  const _Holographic3dPedestalPainter({
    required this.progress,
    required this.primaryColor,
    required this.glowColor,
    required this.isSelected,
    required this.showRadarPulse,
    required this.tiltX,
    required this.tiltY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        !progress.isFinite) {
      return;
    }
    final center = Offset(size.width / 2, size.height / 2 - 2);
    final maxRadius = size.width * 0.50;
    final angle = progress * math.pi * 2.0;

    if (showRadarPulse) {
      for (int i = 0; i < 3; i++) {
        final waveProgress = (progress + i / 3.0) % 1.0;
        final radius = maxRadius * (0.62 + 0.40 * waveProgress);
        final alpha =
            (1.0 - waveProgress).clamp(0.0, 1.0) * (isSelected ? 0.52 : 0.36);

        final paint = Paint()
          ..color = glowColor.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * (1.0 - waveProgress * 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

        canvas.drawCircle(center, radius, paint);
      }
    }

    for (int ringIdx = 0; ringIdx < 2; ringIdx++) {
      final dir = ringIdx == 0 ? 1.0 : -1.0;
      final orbitTilt =
          (ringIdx == 0 ? 0.42 : -0.38) + tiltY * 0.45 + tiltX * 0.25;
      final rx = maxRadius * (ringIdx == 0 ? 0.96 : 0.88);
      final ry = maxRadius * (ringIdx == 0 ? 0.36 : 0.32);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(orbitTilt + math.sin(angle) * 0.08 * dir);

      final orbitRect = Rect.fromCenter(
        center: Offset.zero,
        width: rx * 2.0,
        height: ry * 2.0,
      );
      canvas.drawOval(
        orbitRect,
        Paint()
          ..isAntiAlias = true
          ..color = (ringIdx == 0 ? glowColor : primaryColor).withValues(
            alpha: isSelected ? 0.44 : 0.24,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 1.5 : 1.1,
      );

      final satAngle =
          angle * dir * (ringIdx == 0 ? 1.0 : 2.0) +
          (ringIdx == 1 ? math.pi * 0.5 : 0.0);
      final satPos = Offset(
        rx * math.cos(satAngle),
        ry * math.sin(satAngle),
      );
      canvas.drawCircle(
        satPos,
        size.width * 0.036,
        Paint()
          ..color = glowColor.withValues(alpha: 0.85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        satPos,
        size.width * 0.016,
        Paint()..color = Colors.white,
      );
      canvas.restore();
    }

    final baseCenter = Offset(size.width / 2, size.height - 7);
    final baseRect = Rect.fromCenter(
      center: baseCenter,
      width: size.width * 0.68,
      height: 11,
    );
    canvas.drawOval(
      baseRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            glowColor.withValues(alpha: isSelected ? 0.55 : 0.32),
            primaryColor.withValues(alpha: 0.0),
          ],
        ).createShader(baseRect),
    );
  }

  @override
  bool shouldRepaint(covariant _Holographic3dPedestalPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isSelected != isSelected ||
        oldDelegate.showRadarPulse != showRadarPulse ||
        oldDelegate.tiltX != tiltX ||
        oldDelegate.tiltY != tiltY ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.glowColor != glowColor;
  }
}

class _Photorealistic3dVfxOverlayPainter extends CustomPainter {
  final Icon3dStyle style;
  final double phase;
  final double tiltX;
  final double tiltY;

  const _Photorealistic3dVfxOverlayPainter({
    required this.style,
    required this.phase,
    required this.tiltX,
    required this.tiltY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        !phase.isFinite) {
      return;
    }
    switch (style) {
      case Icon3dStyle.scooterExpress:
        _paintScooterVolumetricVfx(canvas, size);
      case Icon3dStyle.parcelBox:
        _paintParcelLaserVolumetricVfx(canvas, size);
      case Icon3dStyle.gpsPinRadar:
        _paintGpsRadarVolumetricVfx(canvas, size);
      case Icon3dStyle.walletVault:
        _paintWalletGoldVolumetricVfx(canvas, size);
      case Icon3dStyle.hub2hBatch:
        _paintHubBatchVolumetricVfx(canvas, size);
      case Icon3dStyle.cargoTruck:
        _paintCargoTruckVolumetricVfx(canvas, size);
      case Icon3dStyle.foodMarket:
        _paintSparkleShimmerVfx(
          canvas,
          size,
          anchors: const [
            Offset(0.50, 0.48),
            Offset(0.34, 0.36),
            Offset(0.62, 0.30),
          ],
          sparkleColor: const Color(0xFFFFD166),
          shimmerCenter: const Offset(0.52, 0.46),
        );
      case Icon3dStyle.merchantStore:
        _paintMerchantStoreVolumetricVfx(canvas, size);
      case Icon3dStyle.driverPartner:
        _paintDriverPartnerVolumetricVfx(canvas, size);
      case Icon3dStyle.aiAssistant:
        _paintAiAssistantVolumetricVfx(canvas, size);
      case Icon3dStyle.luckyWheel:
        _paintLuckyWheelVolumetricVfx(canvas, size);
      case Icon3dStyle.mysteryBox:
        _paintMysteryBoxVolumetricVfx(canvas, size);
      case Icon3dStyle.voucherFlash:
        _paintSparkleShimmerVfx(
          canvas,
          size,
          anchors: const [
            Offset(0.37, 0.30),
            Offset(0.62, 0.41),
            Offset(0.49, 0.48),
            Offset(0.64, 0.68),
          ],
          sparkleColor: const Color(0xFFFFEA00),
          shimmerCenter: const Offset(0.49, 0.48),
        );
      case Icon3dStyle.adminShieldOps:
      case Icon3dStyle.settingsGear:
        _paintAdminShieldVolumetricVfx(canvas, size);
      case Icon3dStyle.homePortal:
      case Icon3dStyle.createPlus:
      case Icon3dStyle.userProfile:
      case Icon3dStyle.chatSupport:
        _paintSparkleShimmerVfx(
          canvas,
          size,
          anchors: const [
            Offset(0.36, 0.34),
            Offset(0.64, 0.36),
            Offset(0.50, 0.62),
          ],
          sparkleColor: const Color(0xFF67E8F9),
          shimmerCenter: const Offset(0.48, 0.44),
        );
      case Icon3dStyle.orderReceipt:
      case Icon3dStyle.addressBook:
      case Icon3dStyle.shoppingCart:
      case Icon3dStyle.analyticsChart:
      case Icon3dStyle.csvImport:
        _paintSparkleShimmerVfx(
          canvas,
          size,
          anchors: const [
            Offset(0.35, 0.32),
            Offset(0.66, 0.38),
            Offset(0.52, 0.66),
          ],
          sparkleColor: const Color(0xFF6EE7B7),
          shimmerCenter: const Offset(0.50, 0.46),
        );
      case Icon3dStyle.notificationBell:
      case Icon3dStyle.themeSunMoon:
        _paintSparkleShimmerVfx(
          canvas,
          size,
          anchors: const [
            Offset(0.34, 0.32),
            Offset(0.66, 0.30),
            Offset(0.56, 0.66),
          ],
          sparkleColor: const Color(0xFFFDE047),
          shimmerCenter: const Offset(0.46, 0.46),
        );
    }
    _paintAnisotropicGlassRimLight(canvas, size);
  }

  void _paintScooterVolumetricVfx(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final angle = phase * math.pi * 2.0;

    final headlightCenter = Offset(w * 0.33, h * 0.50);
    final beamAlpha = 0.36 + 0.24 * math.sin(angle * 2.0);
    final beamPath = Path()
      ..moveTo(headlightCenter.dx, headlightCenter.dy)
      ..lineTo(w * 0.05, h * 0.58)
      ..lineTo(w * 0.18, h * 0.78)
      ..close();
    canvas.drawPath(
      beamPath,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.6, -0.3),
          radius: 0.9,
          colors: [
            const Color(0xFFFFF3B0).withValues(alpha: beamAlpha),
            const Color(0xFF00B4D8).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, h * 0.40, w * 0.42, h * 0.42))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      headlightCenter,
      w * 0.044,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.80)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    final wheelSpin = phase * math.pi * 8.0;
    for (final wheelPt in [
      Offset(w * 0.30, h * 0.72),
      Offset(w * 0.69, h * 0.56),
    ]) {
      final wheelRect = Rect.fromCircle(center: wheelPt, radius: w * 0.062);
      canvas.drawArc(
        wheelRect,
        wheelSpin,
        math.pi * 0.78,
        false,
        Paint()
          ..color = const Color(0xFF90E0EF).withValues(alpha: 0.76)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.020
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }

    final routeKeypoints = <Offset>[
      Offset(w * 0.76, h * 0.62),
      Offset(w * 0.73, h * 0.69),
      Offset(w * 0.53, h * 0.74),
      Offset(w * 0.56, h * 0.81),
    ];
    for (int i = 0; i < 3; i++) {
      final p = (phase + i / 3.0) % 1.0;
      final orbPos = _samplePolyline(routeKeypoints, p);
      canvas.drawCircle(
        orbPos,
        w * 0.038,
        Paint()
          ..color = const Color(0xFF00F5D4).withValues(alpha: 0.84)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
      );
      canvas.drawCircle(
        orbPos,
        w * 0.015,
        Paint()..color = Colors.white,
      );
    }

    final boxPulse = (math.sin(angle * 2.0) + 1.0) * 0.5;
    canvas.drawCircle(
      Offset(w * 0.70, h * 0.26),
      w * (0.042 + 0.026 * boxPulse),
      Paint()
        ..color = const Color(0xFFFFD166).withValues(alpha: 0.52 * boxPulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  void _paintParcelLaserVolumetricVfx(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final angle = phase * math.pi * 2.0;

    final scanNorm = 0.5 - 0.5 * math.cos(angle * 2.0);
    final scanY = h * (0.32 + 0.44 * scanNorm);

    final curtainRect =
        Rect.fromLTWH(w * 0.18, scanY - h * 0.09, w * 0.64, h * 0.09);
    canvas.drawRect(
      curtainRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFF6B00).withValues(alpha: 0.0),
            const Color(0xFFFF2D55).withValues(alpha: 0.36),
          ],
        ).createShader(curtainRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    canvas.drawLine(
      Offset(w * 0.20, scanY),
      Offset(w * 0.80, scanY),
      Paint()
        ..color = const Color(0xFFFF2D55).withValues(alpha: 0.88)
        ..strokeWidth = h * 0.028
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawLine(
      Offset(w * 0.22, scanY),
      Offset(w * 0.78, scanY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..strokeWidth = h * 0.010
        ..strokeCap = StrokeCap.round,
    );

    final distToBarcode = (scanY - h * 0.59).abs();
    if (distToBarcode < h * 0.16) {
      final glowStrength = (1.0 - distToBarcode / (h * 0.16)).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(w * 0.56, h * 0.59),
        w * 0.09,
        Paint()
          ..color = const Color(0xFF00F5D4).withValues(alpha: 0.72 * glowStrength)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }

    final checkCenter = Offset(w * 0.69, h * 0.27);
    final checkRect = Rect.fromCircle(center: checkCenter, radius: w * 0.148);
    canvas.drawArc(
      checkRect,
      angle,
      math.pi * 0.95,
      false,
      Paint()
        ..color = const Color(0xFF80ED99).withValues(alpha: 0.90)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.024
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  void _paintGpsRadarVolumetricVfx(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sweepAngle = phase * math.pi * 2.0;

    final radarCenter = Offset(w * 0.50, h * 0.56);
    canvas.save();
    canvas.translate(radarCenter.dx, radarCenter.dy);
    canvas.scale(1.0, 0.58);
    final radarRadius = w * 0.30;
    final radarRect = Rect.fromCircle(center: Offset.zero, radius: radarRadius);
    canvas.drawArc(
      radarRect,
      sweepAngle,
      math.pi * 0.60,
      true,
      Paint()
        ..shader = SweepGradient(
          startAngle: sweepAngle,
          endAngle: sweepAngle + math.pi * 0.60,
          colors: [
            const Color(0xFF00F5D4).withValues(alpha: 0.0),
            const Color(0xFF00F5D4).withValues(alpha: 0.68),
          ],
        ).createShader(radarRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    for (int i = 0; i < 2; i++) {
      final p = (phase + i * 0.5) % 1.0;
      final ringRadius = radarRadius * (0.22 + 0.78 * p);
      canvas.drawCircle(
        Offset.zero,
        ringRadius,
        Paint()
          ..color = Colors.white.withValues(alpha: (1.0 - p) * 0.78)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.022
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
    }
    canvas.restore();

    final corePulse = (math.sin(sweepAngle * 2.0) + 1.0) * 0.5;
    final pinCore = Offset(w * 0.51, h * 0.34);
    canvas.drawLine(
      pinCore,
      Offset(w * 0.51, h * 0.08),
      Paint()
        ..color = const Color(0xFF00F5D4).withValues(alpha: 0.38 * corePulse)
        ..strokeWidth = w * 0.025
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      pinCore,
      w * (0.048 + 0.038 * corePulse),
      Paint()
        ..color = const Color(0xFFFFB703).withValues(alpha: 0.72 * corePulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  void _paintWalletGoldVolumetricVfx(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final angle = phase * math.pi * 2.0;

    final sparkleAnchors = <Offset>[
      Offset(w * 0.48, h * 0.21),
      Offset(w * 0.40, h * 0.34),
      Offset(w * 0.55, h * 0.35),
      Offset(w * 0.69, h * 0.64),
    ];
    for (int i = 0; i < sparkleAnchors.length; i++) {
      final localP = (phase * 2.0 + i * 0.25) % 1.0;
      final pos = sparkleAnchors[i].translate(
        math.sin(angle + i) * w * 0.022,
        -localP * h * 0.08,
      );
      final alpha = math.sin(localP * math.pi).clamp(0.0, 1.0);
      canvas.drawCircle(
        pos,
        w * 0.036,
        Paint()
          ..color = const Color(0xFFFFEA00).withValues(alpha: 0.85 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        pos,
        w * 0.014,
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }

    final shieldCenter = Offset(w * 0.70, h * 0.66);
    final shimmerOffset = -w * 0.12 + w * 0.24 * phase;
    canvas.drawCircle(
      shieldCenter.translate(shimmerOffset, shimmerOffset * 0.5),
      w * 0.09,
      Paint()
        ..color = Colors.white.withValues(
          alpha: 0.52 * math.sin(phase * math.pi),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  void _paintHubBatchVolumetricVfx(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final route = <Offset>[
      Offset(w * 0.45, h * 0.36),
      Offset(w * 0.57, h * 0.40),
      Offset(w * 0.43, h * 0.56),
      Offset(w * 0.58, h * 0.59),
    ];
    for (int i = 0; i < 3; i++) {
      final p = (phase + i / 3.0) % 1.0;
      final pt = _samplePolyline(route, p);
      canvas.drawCircle(
        pt,
        w * 0.042,
        Paint()
          ..color = const Color(0xFF22D3EE).withValues(alpha: 0.85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(
        pt,
        w * 0.016,
        Paint()..color = Colors.white,
      );
    }
  }

  void _paintCargoTruckVolumetricVfx(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final angle = phase * math.pi * 2.0;
    final pulse = 0.45 + 0.35 * math.sin(angle * 2.0);
    for (final lamp in [
      Offset(w * 0.23, h * 0.60),
      Offset(w * 0.34, h * 0.66),
    ]) {
      canvas.drawCircle(
        lamp,
        w * 0.046,
        Paint()
          ..color = const Color(0xFFFFF3B0).withValues(alpha: pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    final road = <Offset>[
      Offset(w * 0.78, h * 0.65),
      Offset(w * 0.61, h * 0.71),
      Offset(w * 0.45, h * 0.81),
    ];
    for (int i = 0; i < 2; i++) {
      final p = (phase + i * 0.5) % 1.0;
      final pt = _samplePolyline(road, p);
      canvas.drawCircle(
        pt,
        w * 0.036,
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.80)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  void _paintMerchantStoreVolumetricVfx(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final angle = phase * math.pi * 2.0;
    final warmGlow = 0.28 + 0.22 * math.sin(angle);
    canvas.drawCircle(
      Offset(w * 0.44, h * 0.57),
      w * 0.13,
      Paint()
        ..color = const Color(0xFFFFD166).withValues(alpha: warmGlow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    final checkRect = Rect.fromCircle(
      center: Offset(w * 0.76, h * 0.27),
      radius: w * 0.11,
    );
    canvas.drawArc(
      checkRect,
      angle,
      math.pi * 0.9,
      false,
      Paint()
        ..color = const Color(0xFF6EE7B7).withValues(alpha: 0.88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.022
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  void _paintDriverPartnerVolumetricVfx(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sweep = -w * 0.16 + w * 0.32 * phase;
    canvas.drawCircle(
      Offset(w * 0.42 + sweep, h * 0.50),
      w * 0.085,
      Paint()
        ..color = Colors.white.withValues(
          alpha: 0.48 * math.sin(phase * math.pi),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.save();
    canvas.translate(w * 0.49, h * 0.73);
    canvas.scale(1.0, 0.42);
    for (int i = 0; i < 2; i++) {
      final p = (phase + i * 0.5) % 1.0;
      canvas.drawCircle(
        Offset.zero,
        w * (0.10 + 0.18 * p),
        Paint()
          ..color = const Color(0xFF22D3EE).withValues(alpha: (1.0 - p) * 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.020
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
    }
    canvas.restore();
  }

  void _paintAiAssistantVolumetricVfx(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final angle = phase * math.pi * 2.0;
    final eyePulse = 0.55 + 0.35 * math.sin(angle * 2.0);
    for (final eye in [
      Offset(w * 0.53, h * 0.50),
      Offset(w * 0.64, h * 0.48),
    ]) {
      canvas.drawCircle(
        eye,
        w * 0.036,
        Paint()
          ..color = const Color(0xFF67E8F9).withValues(alpha: eyePulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.save();
    canvas.translate(w * 0.47, h * 0.25);
    canvas.rotate(-0.14);
    final haloRect = Rect.fromCenter(
      center: Offset.zero,
      width: w * 0.26,
      height: h * 0.075,
    );
    canvas.drawArc(
      haloRect,
      angle,
      math.pi * 0.85,
      false,
      Paint()
        ..color = const Color(0xFFFDE047).withValues(alpha: 0.82)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.018
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.restore();
  }

  void _paintLuckyWheelVolumetricVfx(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final angle = phase * math.pi * 2.0;
    final rimRect = Rect.fromCircle(
      center: Offset(w * 0.49, h * 0.48),
      radius: w * 0.27,
    );
    canvas.drawArc(
      rimRect,
      angle,
      math.pi * 0.65,
      false,
      Paint()
        ..color = const Color(0xFFFDE047).withValues(alpha: 0.78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.022
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  void _paintMysteryBoxVolumetricVfx(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final angle = phase * math.pi * 2.0;
    final glowPulse = 0.42 + 0.30 * math.sin(angle * 2.0);
    canvas.drawCircle(
      Offset(w * 0.49, h * 0.50),
      w * 0.12,
      Paint()
        ..color = const Color(0xFF22D3EE).withValues(alpha: glowPulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    _paintSparkleShimmerVfx(
      canvas,
      size,
      anchors: const [
        Offset(0.44, 0.48),
        Offset(0.57, 0.47),
        Offset(0.72, 0.40),
      ],
      sparkleColor: const Color(0xFFFDE047),
      shimmerCenter: const Offset(0.47, 0.28),
    );
  }

  void _paintAdminShieldVolumetricVfx(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final angle = phase * math.pi * 2.0;
    final gemPulse = 0.48 + 0.36 * math.sin(angle * 2.0);
    canvas.drawCircle(
      Offset(w * 0.46, h * 0.50),
      w * 0.075,
      Paint()
        ..color = const Color(0xFF34D399).withValues(alpha: gemPulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.save();
    canvas.translate(w * 0.50, h * 0.49);
    canvas.rotate(-0.42);
    final rx = w * 0.30;
    final ry = h * 0.13;
    final satPos = Offset(rx * math.cos(angle), ry * math.sin(angle));
    canvas.drawCircle(
      satPos,
      w * 0.038,
      Paint()
        ..color = const Color(0xFF22D3EE).withValues(alpha: 0.86)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      satPos,
      w * 0.015,
      Paint()..color = Colors.white,
    );
    canvas.restore();
  }

  void _paintSparkleShimmerVfx(
    Canvas canvas,
    Size size, {
    required List<Offset> anchors,
    required Color sparkleColor,
    required Offset shimmerCenter,
  }) {
    final w = size.width;
    final h = size.height;
    final angle = phase * math.pi * 2.0;
    for (int i = 0; i < anchors.length; i++) {
      final localP = (phase * 2.0 + i * 0.28) % 1.0;
      final pos = Offset(
        w * anchors[i].dx + math.sin(angle + i) * w * 0.020,
        h * anchors[i].dy - localP * h * 0.07,
      );
      final alpha = math.sin(localP * math.pi).clamp(0.0, 1.0);
      canvas.drawCircle(
        pos,
        w * 0.034,
        Paint()
          ..color = sparkleColor.withValues(alpha: 0.82 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        pos,
        w * 0.013,
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }
    final shift = -w * 0.12 + w * 0.24 * phase;
    canvas.drawCircle(
      Offset(w * shimmerCenter.dx + shift, h * shimmerCenter.dy + shift * 0.4),
      w * 0.085,
      Paint()
        ..color = Colors.white.withValues(
          alpha: 0.46 * math.sin(phase * math.pi),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
  }

  void _paintAnisotropicGlassRimLight(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final shiftX = (-tiltY * w * 0.30).clamp(-w * 0.18, w * 0.18);
    final shiftY = (tiltX * h * 0.30).clamp(-h * 0.18, h * 0.18);

    final lensRect = Rect.fromCenter(
      center: Offset(w * 0.34 + shiftX, h * 0.20 + shiftY),
      width: w * 0.44,
      height: h * 0.18,
    );
    canvas.drawOval(
      lensRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.42),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(lensRect),
    );
  }

  Offset _samplePolyline(List<Offset> points, double t) {
    if (points.isEmpty) return Offset.zero;
    if (points.length < 2) return points.first;
    final totalSegments = points.length - 1;
    final scaled = (t.clamp(0.0, 1.0)) * totalSegments;
    final idx = scaled.floor().clamp(0, totalSegments - 1);
    final localT = scaled - idx;
    return Offset.lerp(points[idx], points[idx + 1], localT)!;
  }

  @override
  bool shouldRepaint(covariant _Photorealistic3dVfxOverlayPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.style != style ||
        oldDelegate.tiltX != tiltX ||
        oldDelegate.tiltY != tiltY;
  }
}

class _FallbackOrbPainter extends CustomPainter {
  final Color primary;
  final Color secondary;
  final Color glow;

  const _FallbackOrbPainter({
    required this.primary,
    required this.secondary,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, secondary],
        ).createShader(rect),
    );
    final center = rect.center;
    final r = size.shortestSide * 0.28;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..isAntiAlias = true
        ..color = Colors.white.withValues(alpha: 0.26),
    );
    final diamond = Path()
      ..moveTo(center.dx, center.dy - r * 0.72)
      ..lineTo(center.dx + r * 0.72, center.dy)
      ..lineTo(center.dx, center.dy + r * 0.72)
      ..lineTo(center.dx - r * 0.72, center.dy)
      ..close();
    canvas.drawPath(
      diamond,
      Paint()
        ..isAntiAlias = true
        ..color = Colors.white,
    );
    canvas.drawCircle(
      center.translate(-r * 0.28, -r * 0.28),
      r * 0.16,
      Paint()
        ..isAntiAlias = true
        ..color = glow.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _FallbackOrbPainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.glow != glow;
}
