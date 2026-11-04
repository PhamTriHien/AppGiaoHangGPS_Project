import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'animated_3d_ui_icons.dart';

enum GhstActionKind {
  google,
  login,
  logout,
  user,
  userPlus,
  users,
  key,
  lock,
  unlock,
  shield,
  fingerprint,
  mail,
  pinCode,
  eye,
  eyeOff,
  refresh,
  back,
  forward,
  up,
  down,
  close,
  check,
  checkCircle,
  plus,
  minus,
  zoomIn,
  zoomOut,
  search,
  copy,
  edit,
  delete,
  save,
  send,
  reply,
  swap,
  tune,
  layers,
  fullscreen,
  gps,
  mapPin,
  route,
  directions,
  phone,
  chat,
  bell,
  cart,
  bag,
  store,
  food,
  box,
  scooter,
  truck,
  hub,
  wallet,
  voucher,
  bolt,
  gift,
  wheel,
  sparkle,
  upload,
  download,
  camera,
  image,
  qr,
  scanner,
  print,
  link,
  unlink,
  calendar,
  clock,
  chart,
  grid,
  receipt,
  star,
  heart,
  bookmark,
  flag,
  sun,
  moon,
  autoTheme,
  gear,
  cloudSync,
  cloudOff,
  play,
  pause,
  warning,
  info,
  weather,
  eco,
  radioOn,
  radioOff,
  dot,
  home,
}

class GhstButtonIcon extends StatelessWidget {
  final IconData? legacyIcon;
  final GhstActionKind? actionKind;
  final Icon3dStyle? aiStyle;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final bool preferAi;
  final bool circularAi;
  final bool selected;

  const GhstButtonIcon(
    this.legacyIcon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.preferAi = false,
    this.circularAi = true,
    this.selected = false,
  }) : actionKind = null,
       aiStyle = null;

  const GhstButtonIcon.glyph(
    GhstActionKind this.actionKind, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.selected = false,
  }) : legacyIcon = null,
       aiStyle = null,
       preferAi = false,
       circularAi = true;

  const GhstButtonIcon.ai(
    Icon3dStyle this.aiStyle, {
    super.key,
    this.size,
    this.semanticLabel,
    this.circularAi = true,
    this.selected = false,
  }) : legacyIcon = null,
       actionKind = null,
       color = null,
       preferAi = true;

  factory GhstButtonIcon.forLabel(
    String label, {
    Key? key,
    double? size,
    Color? color,
    bool preferAi = false,
  }) {
    final resolved = resolveKindForLabel(label);
    if (preferAi) {
      final ai = _aiStyleForKind(resolved);
      if (ai != null) {
        return GhstButtonIcon.ai(ai, key: key, size: size);
      }
    }
    return GhstButtonIcon.glyph(
      resolved,
      key: key,
      size: size,
      color: color,
    );
  }

  static GhstActionKind resolveKindForLabel(String rawLabel) {
    final s = rawLabel.trim().toLowerCase();
    if (s.contains('google')) return GhstActionKind.google;
    if (s.contains('met norway')) return GhstActionKind.weather;
    if (s.contains('osrm') || s.contains('openstreetmap')) {
      return GhstActionKind.route;
    }
    if (s.contains('sao chép') || s.contains('chép mã') || s.contains('copy')) {
      return GhstActionKind.copy;
    }
    if (s.contains('đăng xuất') || s.contains('thoát')) {
      return GhstActionKind.logout;
    }
    if (s.contains('đăng ký') ||
        s.contains('tạo tài khoản') ||
        s.contains('thêm nhân') ||
        s.contains('quản trị viên')) {
      return GhstActionKind.userPlus;
    }
    if (s.contains('đăng nhập')) return GhstActionKind.login;
    if (s.contains('trở về') || s.contains('quay lại') || s.contains('trước')) {
      return GhstActionKind.back;
    }
    if (s.contains('tải thêm') || s.contains('cũ hơn')) {
      return GhstActionKind.down;
    }
    if (s.contains('thất bại') || s.contains('sự cố')) {
      return GhstActionKind.warning;
    }
    if (s.contains('phản hồi') || s.contains('trả lời')) {
      return GhstActionKind.reply;
    }
    if (s.contains('huỷ') ||
        s.contains('hủy') ||
        s.contains('đóng') ||
        s.contains('từ chối') ||
        s.contains('bỏ qua')) {
      return GhstActionKind.close;
    }
    if (s.contains('xoá') ||
        s.contains('xóa') ||
        s.contains('gỡ') ||
        s.contains('thu hồi')) {
      return GhstActionKind.delete;
    }
    if (s.contains('tải lại') ||
        s.contains('làm mới') ||
        s.contains('thử lại') ||
        s.contains('kết nối lại') ||
        s.contains('đồng bộ') ||
        s.contains('gửi lại') ||
        s.contains('đặt lại')) {
      return GhstActionKind.refresh;
    }
    if (s.contains('sửa') ||
        s.contains('cập nhật') ||
        s.contains('chỉnh') ||
        s.contains('bản nháp') ||
        s.contains('thay thế') ||
        s.contains('điền')) {
      return GhstActionKind.edit;
    }
    if (s.contains('lưu')) return GhstActionKind.save;
    if (s.contains('tìm')) return GhstActionKind.search;
    if (s.contains('mật khẩu') || s.contains('khôi phục') || s.contains('otp')) {
      return GhstActionKind.key;
    }
    if (s.contains('tải lên') ||
        s.contains('nhập csv') ||
        s.contains('upload')) {
      return GhstActionKind.upload;
    }
    if (s.contains('tải xuống') ||
        s.contains('xuất') ||
        s.contains('mẫu csv')) {
      return GhstActionKind.download;
    }
    if (s.contains('in ') || s.startsWith('in ')) return GhstActionKind.print;
    if (s.contains('chia sẻ') || s.contains('liên kết')) {
      return GhstActionKind.link;
    }
    if (s.contains('thanh toán') ||
        s.contains('nạp') ||
        s.contains('rút') ||
        s.contains('ví') ||
        s.contains('đối soát') ||
        s.contains('hoàn tiền') ||
        s.contains('thu cod') ||
        s.contains('trả tiền shop') ||
        s.contains('thu/chi') ||
        s.contains('đã thu') ||
        s.contains('xu')) {
      return GhstActionKind.wallet;
    }
    if (s.contains('dùng food') || s.contains('quán ăn')) {
      return GhstActionKind.food;
    }
    if (s.contains('dùng ship')) return GhstActionKind.scooter;
    if (s.contains('voucher') ||
        s.contains('ưu đãi') ||
        s.contains('khuyến mãi') ||
        s.contains('phát hành mã') ||
        s.contains('săn') ||
        s.contains('dùng ngay') ||
        s == 'dùng' ||
        s.contains('giảm')) {
      return GhstActionKind.voucher;
    }
    if (s.contains('quay') || s.contains('vòng quay')) {
      return GhstActionKind.wheel;
    }
    if (s.contains('mở hộp') ||
        s.contains('quà') ||
        s.contains('điểm danh') ||
        s.contains('nhận thưởng')) {
      return GhstActionKind.gift;
    }
    if (s.contains('giỏ') || s.contains('thêm vào giỏ')) {
      return GhstActionKind.cart;
    }
    if (s.contains('mua') || s.contains('đặt hàng') || s.contains('chốt đơn')) {
      return GhstActionKind.bag;
    }
    if (s.contains('tạo') ||
        s.contains('thêm') ||
        s.contains('mới') ||
        s.contains('đặt đơn')) {
      return GhstActionKind.plus;
    }
    if (s.contains('tọa độ') || s.contains('gps')) {
      return GhstActionKind.gps;
    }
    if (s.contains('cửa hàng') || s.contains('gian hàng') || s.contains('shop')) {
      return GhstActionKind.store;
    }
    if (s.contains('nhận chuyến') ||
        s.contains('giao') ||
        s.contains('tài xế') ||
        s.contains('lấy hàng')) {
      return GhstActionKind.scooter;
    }
    if (s.contains('bản đồ') ||
        s.contains('hành trình') ||
        s.contains('định vị') ||
        s.contains('địa chỉ')) {
      return GhstActionKind.route;
    }
    if (s.contains('gọi') || s.contains('liên hệ')) return GhstActionKind.phone;
    if (s.contains('gửi')) return GhstActionKind.send;
    if (s.contains('chat') || s.contains('nhắn') || s.contains('hỗ trợ')) {
      return GhstActionKind.chat;
    }
    if (s.contains('ai') || s.contains('tóm tắt') || s.contains('gợi ý')) {
      return GhstActionKind.sparkle;
    }
    if (s.contains('tạm dừng') || s.contains('khoá') || s.contains('khóa')) {
      return GhstActionKind.lock;
    }
    if (s.contains('xem') ||
        s.contains('chi tiết') ||
        s.contains('tiếp') ||
        s.contains('bắt đầu')) {
      return GhstActionKind.forward;
    }
    return GhstActionKind.checkCircle;
  }

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final effectiveSize = size ?? iconTheme.size ?? 18.0;
    if (!effectiveSize.isFinite || effectiveSize <= 0) {
      return const SizedBox.shrink();
    }

    final resolvedAi =
        aiStyle ??
        (preferAi
            ? _aiStyleForKind(actionKind ?? resolveIconData(legacyIcon))
            : null);

    Widget core;
    if (resolvedAi != null) {
      core = GhstAiIcon(
        style: resolvedAi,
        size: effectiveSize,
        circular: circularAi,
        borderRadius: effectiveSize * 0.30,
        selected: selected,
      );
    } else {
      final kind = actionKind ?? resolveIconData(legacyIcon);
      final baseColor =
          color ?? iconTheme.color ?? Theme.of(context).colorScheme.onSurface;
      final opacity = (iconTheme.opacity ?? 1.0).clamp(0.0, 1.0);
      final resolvedColor = opacity < 1.0
          ? baseColor.withValues(alpha: baseColor.a * opacity)
          : baseColor;
      core = SizedBox.square(
        dimension: effectiveSize,
        child: CustomPaint(
          painter: _GhstActionGlyphPainter(
            kind: kind,
            color: resolvedColor,
            selected: selected,
          ),
        ),
      );
    }

    final Widget visual = SizedBox(
      width: effectiveSize,
      height: effectiveSize,
      child: Center(
        widthFactor: 1.0,
        heightFactor: 1.0,
        child: core,
      ),
    );

    if (semanticLabel != null && semanticLabel!.isNotEmpty) {
      return Semantics(
        label: semanticLabel,
        image: true,
        child: ExcludeSemantics(child: visual),
      );
    }
    return ExcludeSemantics(child: visual);
  }

  static Icon3dStyle? _aiStyleForKind(GhstActionKind kind) {
    return switch (kind) {
      GhstActionKind.home => Icon3dStyle.homePortal,
      GhstActionKind.plus => Icon3dStyle.createPlus,
      GhstActionKind.receipt => Icon3dStyle.orderReceipt,
      GhstActionKind.bookmark => Icon3dStyle.addressBook,
      GhstActionKind.bell => Icon3dStyle.notificationBell,
      GhstActionKind.user ||
      GhstActionKind.userPlus ||
      GhstActionKind.users => Icon3dStyle.userProfile,
      GhstActionKind.cart || GhstActionKind.bag => Icon3dStyle.shoppingCart,
      GhstActionKind.chat => Icon3dStyle.chatSupport,
      GhstActionKind.chart => Icon3dStyle.analyticsChart,
      GhstActionKind.upload || GhstActionKind.grid => Icon3dStyle.csvImport,
      GhstActionKind.gear || GhstActionKind.tune => Icon3dStyle.settingsGear,
      GhstActionKind.sun ||
      GhstActionKind.moon ||
      GhstActionKind.autoTheme => Icon3dStyle.themeSunMoon,
      GhstActionKind.scooter => Icon3dStyle.scooterExpress,
      GhstActionKind.box => Icon3dStyle.parcelBox,
      GhstActionKind.gps ||
      GhstActionKind.mapPin ||
      GhstActionKind.route ||
      GhstActionKind.directions => Icon3dStyle.gpsPinRadar,
      GhstActionKind.wallet => Icon3dStyle.walletVault,
      GhstActionKind.hub => Icon3dStyle.hub2hBatch,
      GhstActionKind.truck => Icon3dStyle.cargoTruck,
      GhstActionKind.food => Icon3dStyle.foodMarket,
      GhstActionKind.store => Icon3dStyle.merchantStore,
      GhstActionKind.sparkle => Icon3dStyle.aiAssistant,
      GhstActionKind.wheel => Icon3dStyle.luckyWheel,
      GhstActionKind.gift => Icon3dStyle.mysteryBox,
      GhstActionKind.voucher || GhstActionKind.bolt => Icon3dStyle.voucherFlash,
      GhstActionKind.shield => Icon3dStyle.adminShieldOps,
      _ => null,
    };
  }

  static GhstActionKind resolveIconData(IconData? icon) {
    if (icon == null) return GhstActionKind.sparkle;
    return switch (icon) {
      Icons.home_outlined || Icons.home_rounded => GhstActionKind.home,
      Icons.login_rounded => GhstActionKind.login,
      Icons.logout ||
      Icons.logout_rounded ||
      Icons.power_settings_new_rounded => GhstActionKind.logout,
      Icons.person_add_alt ||
      Icons.person_add_alt_1 ||
      Icons.person_add_outlined => GhstActionKind.userPlus,
      Icons.people_alt_outlined ||
      Icons.people_outline_rounded ||
      Icons.group_outlined => GhstActionKind.users,
      Icons.person ||
      Icons.person_outline ||
      Icons.person_outline_rounded ||
      Icons.person_rounded ||
      Icons.account_circle_outlined ||
      Icons.manage_accounts_outlined ||
      Icons.manage_accounts_rounded ||
      Icons.badge_outlined ||
      Icons.face_retouching_natural_rounded ||
      Icons.assignment_ind_outlined => GhstActionKind.user,
      Icons.vpn_key_outlined => GhstActionKind.key,
      Icons.lock_open || Icons.lock_open_rounded => GhstActionKind.unlock,
      Icons.lock_outline ||
      Icons.lock_outline_rounded ||
      Icons.lock_person_rounded ||
      Icons.lock_reset_rounded ||
      Icons.lock_rounded ||
      Icons.sync_lock_outlined => GhstActionKind.lock,
      Icons.shield_outlined ||
      Icons.admin_panel_settings_outlined ||
      Icons.admin_panel_settings_rounded ||
      Icons.add_moderator_outlined ||
      Icons.verified_user_outlined ||
      Icons.verified_user_rounded ||
      Icons.gpp_bad_outlined => GhstActionKind.shield,
      Icons.fingerprint_rounded => GhstActionKind.fingerprint,
      Icons.alternate_email ||
      Icons.alternate_email_rounded ||
      Icons.email_outlined ||
      Icons.mail_outline_rounded ||
      Icons.mark_email_read_outlined ||
      Icons.drafts_outlined ||
      Icons.contact_mail_outlined => GhstActionKind.mail,
      Icons.pin_outlined => GhstActionKind.pinCode,
      Icons.visibility_off_outlined => GhstActionKind.eyeOff,
      Icons.visibility_outlined || Icons.preview_outlined => GhstActionKind.eye,
      Icons.refresh ||
      Icons.refresh_rounded ||
      Icons.autorenew ||
      Icons.replay ||
      Icons.replay_rounded ||
      Icons.sync ||
      Icons.sync_rounded => GhstActionKind.refresh,
      Icons.arrow_back_ios_new_rounded ||
      Icons.arrow_back_rounded ||
      Icons.chevron_left ||
      Icons.undo ||
      Icons.undo_rounded ||
      Icons.keyboard_return_rounded => GhstActionKind.back,
      Icons.arrow_forward ||
      Icons.arrow_forward_rounded ||
      Icons.chevron_right ||
      Icons.double_arrow ||
      Icons.launch_rounded ||
      Icons.north_east_rounded ||
      Icons.open_in_browser_rounded ||
      Icons.open_in_new ||
      Icons.open_in_new_rounded ||
      Icons.touch_app_outlined ||
      Icons.touch_app_rounded => GhstActionKind.forward,
      Icons.expand_less_rounded || Icons.north_rounded => GhstActionKind.up,
      Icons.arrow_drop_down_rounded ||
      Icons.expand_more_rounded ||
      Icons.keyboard_arrow_down_rounded ||
      Icons.south_rounded => GhstActionKind.down,
      Icons.cancel ||
      Icons.cancel_outlined ||
      Icons.cancel_presentation_rounded ||
      Icons.cancel_rounded ||
      Icons.clear ||
      Icons.clear_rounded ||
      Icons.close ||
      Icons.close_rounded => GhstActionKind.close,
      Icons.check_circle ||
      Icons.check_circle_outline ||
      Icons.check_circle_outline_rounded ||
      Icons.check_circle_rounded ||
      Icons.verified_outlined ||
      Icons.verified_rounded ||
      Icons.task_alt ||
      Icons.task_alt_rounded ||
      Icons.done_all_rounded ||
      Icons.fact_check_outlined ||
      Icons.playlist_add_check ||
      Icons.playlist_add_check_rounded ||
      Icons.check_box => GhstActionKind.checkCircle,
      Icons.check || Icons.check_rounded => GhstActionKind.check,
      Icons.add ||
      Icons.add_box_outlined ||
      Icons.add_box_rounded ||
      Icons.add_circle_outline ||
      Icons.add_circle_rounded ||
      Icons.note_add_outlined => GhstActionKind.plus,
      Icons.remove => GhstActionKind.minus,
      Icons.zoom_in || Icons.zoom_in_rounded => GhstActionKind.zoomIn,
      Icons.zoom_out || Icons.zoom_out_rounded => GhstActionKind.zoomOut,
      Icons.search ||
      Icons.search_rounded ||
      Icons.find_in_page_outlined ||
      Icons.manage_search_rounded ||
      Icons.person_search_outlined ||
      Icons.travel_explore_rounded => GhstActionKind.search,
      Icons.content_copy_outlined ||
      Icons.copy ||
      Icons.copy_outlined ||
      Icons.copy_rounded => GhstActionKind.copy,
      Icons.edit_location_alt_outlined ||
      Icons.edit_note_outlined ||
      Icons.edit_outlined ||
      Icons.edit_road_rounded => GhstActionKind.edit,
      Icons.delete_outline ||
      Icons.delete_sweep_outlined ||
      Icons.remove_circle_outline ||
      Icons.person_remove_outlined ||
      Icons.remove_moderator_outlined => GhstActionKind.delete,
      Icons.save_outlined => GhstActionKind.save,
      Icons.send ||
      Icons.send_outlined ||
      Icons.send_rounded => GhstActionKind.send,
      Icons.reply_outlined ||
      Icons.reply_rounded ||
      Icons.assignment_return_outlined ||
      Icons.assignment_returned_outlined => GhstActionKind.reply,
      Icons.swap_horiz ||
      Icons.swap_horiz_rounded ||
      Icons.sync_alt ||
      Icons.sync_alt_rounded ||
      Icons.compare_arrows ||
      Icons.switch_account_outlined => GhstActionKind.swap,
      Icons.tune_rounded ||
      Icons.filter_alt_off_outlined ||
      Icons.exposure_outlined => GhstActionKind.tune,
      Icons.layers_outlined ||
      Icons.map_outlined ||
      Icons.map_rounded ||
      Icons.panorama_outlined ||
      Icons.satellite_alt => GhstActionKind.layers,
      Icons.fullscreen_rounded ||
      Icons.open_in_full_rounded => GhstActionKind.fullscreen,
      Icons.gps_fixed ||
      Icons.gps_fixed_rounded ||
      Icons.my_location ||
      Icons.my_location_outlined ||
      Icons.my_location_rounded ||
      Icons.location_searching_outlined ||
      Icons.location_searching_rounded ||
      Icons.center_focus_strong_rounded ||
      Icons.radar_rounded ||
      Icons.sensors_rounded ||
      Icons.track_changes_rounded => GhstActionKind.gps,
      Icons.location_on ||
      Icons.location_on_outlined ||
      Icons.location_on_rounded ||
      Icons.place ||
      Icons.place_outlined ||
      Icons.place_rounded ||
      Icons.pin_drop_outlined ||
      Icons.add_location_alt_outlined ||
      Icons.person_pin_circle_outlined ||
      Icons.share_location_rounded ||
      Icons.trip_origin_rounded ||
      Icons.where_to_vote_rounded => GhstActionKind.mapPin,
      Icons.alt_route ||
      Icons.alt_route_outlined ||
      Icons.alt_route_rounded ||
      Icons.route_outlined ||
      Icons.route_rounded ||
      Icons.polyline_rounded ||
      Icons.timeline_rounded ||
      Icons.turn_right ||
      Icons.turn_right_rounded ||
      Icons.call_split => GhstActionKind.route,
      Icons.directions_outlined ||
      Icons.navigation_outlined ||
      Icons.navigation_rounded ||
      Icons.explore_outlined => GhstActionKind.directions,
      Icons.call_outlined ||
      Icons.phone ||
      Icons.phone_forwarded_outlined ||
      Icons.phone_in_talk_outlined ||
      Icons.phone_iphone_rounded ||
      Icons.phone_outlined => GhstActionKind.phone,
      Icons.chat_bubble_outline ||
      Icons.chat_bubble_outline_rounded ||
      Icons.chat_bubble_rounded ||
      Icons.forum_outlined ||
      Icons.forum_rounded ||
      Icons.sms_outlined ||
      Icons.reviews_outlined ||
      Icons.support_agent_outlined ||
      Icons.support_agent_rounded ||
      Icons.sentiment_very_satisfied_rounded => GhstActionKind.chat,
      Icons.notification_important_outlined ||
      Icons.notifications_active_outlined ||
      Icons.notifications_none ||
      Icons.notifications_none_outlined ||
      Icons.notifications_none_rounded ||
      Icons.notifications_outlined ||
      Icons.campaign_outlined => GhstActionKind.bell,
      Icons.add_shopping_cart ||
      Icons.shopping_cart_outlined ||
      Icons.shopping_cart_rounded => GhstActionKind.cart,
      Icons.shopping_bag_outlined ||
      Icons.shopping_bag_rounded => GhstActionKind.bag,
      Icons.add_business ||
      Icons.add_business_outlined ||
      Icons.business_center_outlined ||
      Icons.business_outlined ||
      Icons.business_rounded ||
      Icons.storefront_outlined ||
      Icons.storefront_rounded ||
      Icons.warehouse_outlined => GhstActionKind.store,
      Icons.fastfood_outlined ||
      Icons.no_meals_outlined ||
      Icons.restaurant_menu_rounded ||
      Icons.restaurant_outlined => GhstActionKind.food,
      Icons.folder_open ||
      Icons.folder_open_outlined ||
      Icons.inbox_outlined ||
      Icons.inventory_2_outlined ||
      Icons.inventory_2_rounded ||
      Icons.inventory_outlined ||
      Icons.move_to_inbox_outlined => GhstActionKind.box,
      Icons.delivery_dining ||
      Icons.delivery_dining_outlined ||
      Icons.delivery_dining_rounded ||
      Icons.electric_moped_rounded ||
      Icons.sports_motorsports_rounded ||
      Icons.two_wheeler ||
      Icons.two_wheeler_outlined ||
      Icons.two_wheeler_rounded => GhstActionKind.scooter,
      Icons.fire_truck_rounded ||
      Icons.local_shipping_outlined ||
      Icons.local_shipping_rounded => GhstActionKind.truck,
      Icons.computer_outlined ||
      Icons.dns_outlined ||
      Icons.hub_outlined ||
      Icons.hub_rounded ||
      Icons.public_rounded ||
      Icons.webhook_outlined ||
      Icons.webhook_rounded => GhstActionKind.hub,
      Icons.account_balance_outlined ||
      Icons.account_balance_rounded ||
      Icons.account_balance_wallet_outlined ||
      Icons.account_balance_wallet_rounded ||
      Icons.calculate_outlined ||
      Icons.credit_card ||
      Icons.credit_card_rounded ||
      Icons.monetization_on_outlined ||
      Icons.monetization_on_rounded ||
      Icons.paid_outlined ||
      Icons.payment ||
      Icons.payments_outlined ||
      Icons.price_change_outlined ||
      Icons.savings_outlined ||
      Icons.savings_rounded => GhstActionKind.wallet,
      Icons.confirmation_num_outlined ||
      Icons.confirmation_number_outlined ||
      Icons.confirmation_number_rounded ||
      Icons.local_offer_outlined ||
      Icons.local_offer_rounded => GhstActionKind.voucher,
      Icons.battery_charging_full_rounded ||
      Icons.bolt_rounded ||
      Icons.flash_on_outlined ||
      Icons.flash_on_rounded ||
      Icons.local_fire_department_rounded => GhstActionKind.bolt,
      Icons.cake_outlined ||
      Icons.card_giftcard_outlined ||
      Icons.card_giftcard_rounded ||
      Icons.redeem_rounded => GhstActionKind.gift,
      Icons.casino_outlined || Icons.casino_rounded => GhstActionKind.wheel,
      Icons.auto_awesome_outlined ||
      Icons.auto_awesome_rounded ||
      Icons.emoji_events_rounded ||
      Icons.extension_outlined ||
      Icons.stars_rounded ||
      Icons.workspace_premium_rounded => GhstActionKind.sparkle,
      Icons.cloud_upload_outlined ||
      Icons.publish_rounded ||
      Icons.system_update_alt ||
      Icons.upload_file_outlined ||
      Icons.upload_file_rounded ||
      Icons.upload_rounded => GhstActionKind.upload,
      Icons.download ||
      Icons.download_done_rounded ||
      Icons.download_outlined => GhstActionKind.download,
      Icons.add_a_photo_outlined ||
      Icons.camera_alt_outlined ||
      Icons.camera_alt_rounded ||
      Icons.photo_camera_outlined => GhstActionKind.camera,
      Icons.add_photo_alternate_outlined ||
      Icons.broken_image_outlined ||
      Icons.image_not_supported_outlined ||
      Icons.image_outlined ||
      Icons.image_rounded ||
      Icons.photo_outlined => GhstActionKind.image,
      Icons.qr_code_2_rounded => GhstActionKind.qr,
      Icons.document_scanner_outlined ||
      Icons.qr_code_scanner_rounded => GhstActionKind.scanner,
      Icons.print || Icons.print_outlined => GhstActionKind.print,
      Icons.add_link ||
      Icons.attach_file ||
      Icons.share_outlined => GhstActionKind.link,
      Icons.link_off => GhstActionKind.unlink,
      Icons.calendar_month_outlined ||
      Icons.calendar_month_rounded ||
      Icons.calendar_today_outlined ||
      Icons.event_available_outlined ||
      Icons.event_available_rounded ||
      Icons.event_outlined => GhstActionKind.calendar,
      Icons.access_time_rounded ||
      Icons.history ||
      Icons.history_edu_outlined ||
      Icons.history_edu_rounded ||
      Icons.history_outlined ||
      Icons.history_rounded ||
      Icons.hourglass_top_rounded ||
      Icons.pending_actions_outlined ||
      Icons.pending_actions_rounded ||
      Icons.pending_outlined ||
      Icons.schedule ||
      Icons.timelapse_rounded ||
      Icons.timer_outlined => GhstActionKind.clock,
      Icons.analytics_outlined ||
      Icons.bar_chart_outlined ||
      Icons.insights_outlined ||
      Icons.insights_rounded ||
      Icons.monitor_heart_outlined => GhstActionKind.chart,
      Icons.apps_rounded ||
      Icons.grid_view_rounded ||
      Icons.hexagon_outlined ||
      Icons.space_dashboard_outlined ||
      Icons.space_dashboard_rounded ||
      Icons.table_view => GhstActionKind.grid,
      Icons.assignment_late_outlined ||
      Icons.description_outlined ||
      Icons.insert_drive_file_outlined ||
      Icons.menu_book_outlined ||
      Icons.notes_rounded ||
      Icons.receipt_long_outlined ||
      Icons.receipt_long_rounded ||
      Icons.sticky_note_2_outlined => GhstActionKind.receipt,
      Icons.star ||
      Icons.star_border ||
      Icons.star_border_rounded ||
      Icons.star_outline ||
      Icons.star_outline_rounded ||
      Icons.star_rounded => GhstActionKind.star,
      Icons.favorite || Icons.favorite_outline => GhstActionKind.heart,
      Icons.bookmark_add_outlined ||
      Icons.bookmark_added ||
      Icons.bookmark_border_rounded ||
      Icons.bookmark_rounded ||
      Icons.bookmarks_outlined ||
      Icons.bookmarks_rounded => GhstActionKind.bookmark,
      Icons.flag ||
      Icons.flag_outlined ||
      Icons.flag_rounded => GhstActionKind.flag,
      Icons.light_mode_rounded ||
      Icons.wb_sunny_outlined ||
      Icons.wb_sunny_rounded => GhstActionKind.sun,
      Icons.dark_mode_rounded ||
      Icons.nights_stay_rounded => GhstActionKind.moon,
      Icons.brightness_auto_rounded => GhstActionKind.autoTheme,
      Icons.settings_outlined => GhstActionKind.gear,
      Icons.cloud_done_outlined ||
      Icons.cloud_outlined ||
      Icons.cloud_sync_outlined ||
      Icons.network_check_outlined => GhstActionKind.cloudSync,
      Icons.cloud_off_outlined ||
      Icons.portable_wifi_off_outlined ||
      Icons.sync_problem_outlined ||
      Icons.wifi_off_rounded => GhstActionKind.cloudOff,
      Icons.play_arrow || Icons.play_circle_outline => GhstActionKind.play,
      Icons.pause_circle_outline ||
      Icons.pause_circle_outline_rounded => GhstActionKind.pause,
      Icons.error_outline_rounded ||
      Icons.report_problem_outlined ||
      Icons.warning_amber_rounded => GhstActionKind.warning,
      Icons.info_outline => GhstActionKind.info,
      Icons.thunderstorm_outlined => GhstActionKind.weather,
      Icons.eco_rounded || Icons.park_rounded => GhstActionKind.eco,
      Icons.radio_button_checked_rounded => GhstActionKind.radioOn,
      Icons.check_box_outline_blank ||
      Icons.circle_outlined ||
      Icons.radio_button_unchecked => GhstActionKind.radioOff,
      Icons.circle => GhstActionKind.dot,
      _ => GhstActionKind.sparkle,
    };
  }
}

class _GhstActionGlyphPainter extends CustomPainter {
  final GhstActionKind kind;
  final Color color;
  final bool selected;

  const _GhstActionGlyphPainter({
    required this.kind,
    required this.color,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (s <= 0 || !s.isFinite) return;
    if (kind == GhstActionKind.google) {
      _paintGoogleEmblem(canvas, size);
      return;
    }

    final sw = (s * (selected ? 0.114 : 0.104)).clamp(1.55, 2.65);
    final stroke = Paint()
      ..isAntiAlias = true
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillSoft = Paint()
      ..isAntiAlias = true
      ..color = color.withValues(alpha: selected ? 0.30 : 0.22)
      ..style = PaintingStyle.fill;

    final fillSolid = Paint()
      ..isAntiAlias = true
      ..color = color
      ..style = PaintingStyle.fill;

    final c = Offset(size.width * 0.5, size.height * 0.5);
    double p(double f) => s * f;

    switch (kind) {
      case GhstActionKind.google:
        break;
      case GhstActionKind.home:
        final roof = Path()
          ..moveTo(p(0.14), p(0.47))
          ..lineTo(p(0.50), p(0.16))
          ..lineTo(p(0.86), p(0.47));
        final body = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.24), p(0.43), p(0.76), p(0.84)),
          Radius.circular(p(0.08)),
        );
        canvas.drawRRect(body, fillSoft);
        canvas.drawRRect(body, stroke);
        canvas.drawPath(roof, stroke);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(p(0.43), p(0.58), p(0.57), p(0.84)),
            Radius.circular(p(0.05)),
          ),
          stroke,
        );
      case GhstActionKind.login:
        final frame = Path()
          ..moveTo(p(0.52), p(0.18))
          ..lineTo(p(0.78), p(0.18))
          ..quadraticBezierTo(p(0.84), p(0.18), p(0.84), p(0.24))
          ..lineTo(p(0.84), p(0.76))
          ..quadraticBezierTo(p(0.84), p(0.82), p(0.78), p(0.82))
          ..lineTo(p(0.52), p(0.82));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(p(0.52), p(0.20), p(0.84), p(0.80)),
            Radius.circular(p(0.08)),
          ),
          fillSoft,
        );
        canvas.drawPath(frame, stroke);
        canvas.drawLine(Offset(p(0.16), p(0.50)), Offset(p(0.62), p(0.50)), stroke);
        final head = Path()
          ..moveTo(p(0.46), p(0.34))
          ..lineTo(p(0.63), p(0.50))
          ..lineTo(p(0.46), p(0.66));
        canvas.drawPath(head, stroke);
      case GhstActionKind.logout:
        final frame = Path()
          ..moveTo(p(0.48), p(0.18))
          ..lineTo(p(0.24), p(0.18))
          ..quadraticBezierTo(p(0.18), p(0.18), p(0.18), p(0.24))
          ..lineTo(p(0.18), p(0.76))
          ..quadraticBezierTo(p(0.18), p(0.82), p(0.24), p(0.82))
          ..lineTo(p(0.48), p(0.82));
        canvas.drawPath(frame, stroke);
        canvas.drawLine(Offset(p(0.38), p(0.50)), Offset(p(0.84), p(0.50)), stroke);
        final head = Path()
          ..moveTo(p(0.68), p(0.34))
          ..lineTo(p(0.84), p(0.50))
          ..lineTo(p(0.68), p(0.66));
        canvas.drawPath(head, stroke);
      case GhstActionKind.user:
        canvas.drawCircle(Offset(p(0.50), p(0.33)), p(0.16), fillSoft);
        canvas.drawCircle(Offset(p(0.50), p(0.33)), p(0.16), stroke);
        final shoulders = Path()
          ..moveTo(p(0.20), p(0.82))
          ..quadraticBezierTo(p(0.22), p(0.57), p(0.50), p(0.57))
          ..quadraticBezierTo(p(0.78), p(0.57), p(0.80), p(0.82));
        canvas.drawPath(shoulders, fillSoft);
        canvas.drawPath(shoulders, stroke);
      case GhstActionKind.userPlus:
        canvas.drawCircle(Offset(p(0.41), p(0.34)), p(0.15), fillSoft);
        canvas.drawCircle(Offset(p(0.41), p(0.34)), p(0.15), stroke);
        final shoulders = Path()
          ..moveTo(p(0.14), p(0.82))
          ..quadraticBezierTo(p(0.16), p(0.58), p(0.41), p(0.58))
          ..quadraticBezierTo(p(0.66), p(0.58), p(0.68), p(0.82));
        canvas.drawPath(shoulders, fillSoft);
        canvas.drawPath(shoulders, stroke);
        canvas.drawLine(Offset(p(0.77), p(0.34)), Offset(p(0.77), p(0.56)), stroke);
        canvas.drawLine(Offset(p(0.66), p(0.45)), Offset(p(0.88), p(0.45)), stroke);
      case GhstActionKind.users:
        canvas.drawCircle(Offset(p(0.38), p(0.34)), p(0.14), fillSoft);
        canvas.drawCircle(Offset(p(0.38), p(0.34)), p(0.14), stroke);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(p(0.66), p(0.36)), radius: p(0.11)),
          -math.pi * 0.45,
          math.pi * 0.9,
          false,
          stroke,
        );
        final main = Path()
          ..moveTo(p(0.14), p(0.80))
          ..quadraticBezierTo(p(0.16), p(0.58), p(0.38), p(0.58))
          ..quadraticBezierTo(p(0.60), p(0.58), p(0.62), p(0.80));
        canvas.drawPath(main, stroke);
        final side = Path()
          ..moveTo(p(0.64), p(0.59))
          ..quadraticBezierTo(p(0.84), p(0.60), p(0.86), p(0.80));
        canvas.drawPath(side, stroke);
      case GhstActionKind.key:
        canvas.drawCircle(Offset(p(0.34), p(0.54)), p(0.17), fillSoft);
        canvas.drawCircle(Offset(p(0.34), p(0.54)), p(0.17), stroke);
        canvas.drawCircle(Offset(p(0.32), p(0.54)), sw * 0.55, fillSolid);
        final shaft = Path()
          ..moveTo(p(0.48), p(0.44))
          ..lineTo(p(0.84), p(0.24))
          ..lineTo(p(0.86), p(0.36))
          ..moveTo(p(0.69), p(0.33))
          ..lineTo(p(0.74), p(0.44));
        canvas.drawPath(shaft, stroke);
      case GhstActionKind.lock:
      case GhstActionKind.unlock:
        final body = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.22), p(0.46), p(0.78), p(0.84)),
          Radius.circular(p(0.10)),
        );
        canvas.drawRRect(body, fillSoft);
        canvas.drawRRect(body, stroke);
        final shackle = Path();
        if (kind == GhstActionKind.lock) {
          shackle
            ..moveTo(p(0.34), p(0.46))
            ..lineTo(p(0.34), p(0.33))
            ..arcToPoint(
              Offset(p(0.66), p(0.33)),
              radius: Radius.circular(p(0.16)),
            )
            ..lineTo(p(0.66), p(0.46));
        } else {
          shackle
            ..moveTo(p(0.34), p(0.46))
            ..lineTo(p(0.34), p(0.31))
            ..arcToPoint(
              Offset(p(0.68), p(0.28)),
              radius: Radius.circular(p(0.16)),
            );
        }
        canvas.drawPath(shackle, stroke);
        canvas.drawCircle(Offset(p(0.50), p(0.63)), sw * 0.65, fillSolid);
      case GhstActionKind.shield:
        final shield = Path()
          ..moveTo(p(0.50), p(0.14))
          ..lineTo(p(0.80), p(0.25))
          ..lineTo(p(0.80), p(0.50))
          ..quadraticBezierTo(p(0.79), p(0.75), p(0.50), p(0.87))
          ..quadraticBezierTo(p(0.21), p(0.75), p(0.20), p(0.50))
          ..lineTo(p(0.20), p(0.25))
          ..close();
        canvas.drawPath(shield, fillSoft);
        canvas.drawPath(shield, stroke);
        final ck = Path()
          ..moveTo(p(0.37), p(0.51))
          ..lineTo(p(0.47), p(0.61))
          ..lineTo(p(0.64), p(0.41));
        canvas.drawPath(ck, stroke);
      case GhstActionKind.fingerprint:
        for (final r in [0.14, 0.24, 0.34]) {
          canvas.drawArc(
            Rect.fromCircle(center: Offset(p(0.50), p(0.54)), radius: p(r)),
            -math.pi * 0.85,
            math.pi * 1.45,
            false,
            stroke,
          );
        }
        canvas.drawLine(Offset(p(0.50), p(0.46)), Offset(p(0.50), p(0.74)), stroke);
      case GhstActionKind.mail:
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.15), p(0.25), p(0.85), p(0.75)),
          Radius.circular(p(0.09)),
        );
        canvas.drawRRect(rect, fillSoft);
        canvas.drawRRect(rect, stroke);
        final flap = Path()
          ..moveTo(p(0.18), p(0.30))
          ..lineTo(p(0.50), p(0.54))
          ..lineTo(p(0.82), p(0.30));
        canvas.drawPath(flap, stroke);
      case GhstActionKind.pinCode:
        final box = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.14), p(0.28), p(0.86), p(0.72)),
          Radius.circular(p(0.10)),
        );
        canvas.drawRRect(box, fillSoft);
        canvas.drawRRect(box, stroke);
        for (final x in [0.32, 0.50, 0.68]) {
          canvas.drawCircle(Offset(p(x), p(0.50)), sw * 0.72, fillSolid);
        }
      case GhstActionKind.eye:
      case GhstActionKind.eyeOff:
        final lid = Path()
          ..moveTo(p(0.12), p(0.50))
          ..quadraticBezierTo(p(0.50), p(0.18), p(0.88), p(0.50))
          ..quadraticBezierTo(p(0.50), p(0.82), p(0.12), p(0.50));
        canvas.drawPath(lid, fillSoft);
        canvas.drawPath(lid, stroke);
        canvas.drawCircle(c, p(0.12), stroke);
        if (kind == GhstActionKind.eyeOff) {
          canvas.drawLine(Offset(p(0.20), p(0.80)), Offset(p(0.80), p(0.20)), stroke);
        }
      case GhstActionKind.refresh:
        final r = Rect.fromCircle(center: c, radius: p(0.32));
        canvas.drawCircle(c, p(0.20), fillSoft);
        canvas.drawArc(r, -math.pi * 0.80, math.pi * 1.25, false, stroke);
        canvas.drawArc(r, math.pi * 0.20, math.pi * 1.25, false, stroke);
        final a1 = Path()
          ..moveTo(p(0.66), p(0.16))
          ..lineTo(p(0.79), p(0.31))
          ..lineTo(p(0.61), p(0.34));
        final a2 = Path()
          ..moveTo(p(0.34), p(0.84))
          ..lineTo(p(0.21), p(0.69))
          ..lineTo(p(0.39), p(0.66));
        canvas.drawPath(a1, stroke);
        canvas.drawPath(a2, stroke);
      case GhstActionKind.back:
        canvas.drawCircle(c, p(0.36), fillSoft);
        canvas.drawLine(Offset(p(0.74), p(0.50)), Offset(p(0.26), p(0.50)), stroke);
        final head = Path()
          ..moveTo(p(0.46), p(0.30))
          ..lineTo(p(0.25), p(0.50))
          ..lineTo(p(0.46), p(0.70));
        canvas.drawPath(head, stroke);
      case GhstActionKind.forward:
        canvas.drawCircle(c, p(0.36), fillSoft);
        canvas.drawLine(Offset(p(0.26), p(0.50)), Offset(p(0.74), p(0.50)), stroke);
        final head = Path()
          ..moveTo(p(0.54), p(0.30))
          ..lineTo(p(0.75), p(0.50))
          ..lineTo(p(0.54), p(0.70));
        canvas.drawPath(head, stroke);
      case GhstActionKind.up:
        canvas.drawCircle(c, p(0.36), fillSoft);
        final ch = Path()
          ..moveTo(p(0.26), p(0.58))
          ..lineTo(p(0.50), p(0.34))
          ..lineTo(p(0.74), p(0.58));
        canvas.drawPath(ch, stroke);
      case GhstActionKind.down:
        canvas.drawCircle(c, p(0.36), fillSoft);
        final ch = Path()
          ..moveTo(p(0.26), p(0.42))
          ..lineTo(p(0.50), p(0.66))
          ..lineTo(p(0.74), p(0.42));
        canvas.drawPath(ch, stroke);
      case GhstActionKind.close:
        canvas.drawCircle(c, p(0.38), fillSoft);
        canvas.drawLine(Offset(p(0.30), p(0.30)), Offset(p(0.70), p(0.70)), stroke);
        canvas.drawLine(Offset(p(0.70), p(0.30)), Offset(p(0.30), p(0.70)), stroke);
      case GhstActionKind.check:
        final ck = Path()
          ..moveTo(p(0.20), p(0.52))
          ..lineTo(p(0.42), p(0.73))
          ..lineTo(p(0.80), p(0.28));
        canvas.drawPath(ck, stroke);
      case GhstActionKind.checkCircle:
        canvas.drawCircle(c, p(0.37), fillSoft);
        canvas.drawCircle(c, p(0.37), stroke);
        final ck = Path()
          ..moveTo(p(0.34), p(0.51))
          ..lineTo(p(0.46), p(0.63))
          ..lineTo(p(0.67), p(0.39));
        canvas.drawPath(ck, stroke);
      case GhstActionKind.plus:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: p(0.74), height: p(0.74)),
            Radius.circular(p(0.20)),
          ),
          fillSoft,
        );
        canvas.drawLine(Offset(p(0.50), p(0.24)), Offset(p(0.50), p(0.76)), stroke);
        canvas.drawLine(Offset(p(0.24), p(0.50)), Offset(p(0.76), p(0.50)), stroke);
      case GhstActionKind.minus:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: p(0.74), height: p(0.74)),
            Radius.circular(p(0.20)),
          ),
          fillSoft,
        );
        canvas.drawLine(Offset(p(0.24), p(0.50)), Offset(p(0.76), p(0.50)), stroke);
      case GhstActionKind.zoomIn:
      case GhstActionKind.zoomOut:
      case GhstActionKind.search:
        final glass = Offset(p(0.44), p(0.44));
        canvas.drawCircle(glass, p(0.25), fillSoft);
        canvas.drawCircle(glass, p(0.25), stroke);
        canvas.drawLine(Offset(p(0.62), p(0.62)), Offset(p(0.84), p(0.84)), stroke);
        if (kind == GhstActionKind.zoomIn || kind == GhstActionKind.zoomOut) {
          canvas.drawLine(Offset(p(0.34), p(0.44)), Offset(p(0.54), p(0.44)), stroke);
          if (kind == GhstActionKind.zoomIn) {
            canvas.drawLine(Offset(p(0.44), p(0.34)), Offset(p(0.44), p(0.54)), stroke);
          }
        }
      case GhstActionKind.copy:
        final front = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.32), p(0.30), p(0.82), p(0.84)),
          Radius.circular(p(0.08)),
        );
        canvas.drawRRect(front, fillSoft);
        canvas.drawRRect(front, stroke);
        final backSheet = Path()
          ..moveTo(p(0.64), p(0.28))
          ..lineTo(p(0.64), p(0.20))
          ..quadraticBezierTo(p(0.64), p(0.15), p(0.58), p(0.15))
          ..lineTo(p(0.24), p(0.15))
          ..quadraticBezierTo(p(0.18), p(0.15), p(0.18), p(0.21))
          ..lineTo(p(0.18), p(0.66))
          ..quadraticBezierTo(p(0.18), p(0.72), p(0.24), p(0.72))
          ..lineTo(p(0.30), p(0.72));
        canvas.drawPath(backSheet, stroke);
      case GhstActionKind.edit:
        final pen = Path()
          ..moveTo(p(0.20), p(0.80))
          ..lineTo(p(0.26), p(0.60))
          ..lineTo(p(0.66), p(0.20))
          ..lineTo(p(0.80), p(0.34))
          ..lineTo(p(0.40), p(0.74))
          ..close();
        canvas.drawPath(pen, fillSoft);
        canvas.drawPath(pen, stroke);
        canvas.drawLine(Offset(p(0.56), p(0.30)), Offset(p(0.70), p(0.44)), stroke);
      case GhstActionKind.delete:
        final bin = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.27), p(0.32), p(0.73), p(0.84)),
          Radius.circular(p(0.08)),
        );
        canvas.drawRRect(bin, fillSoft);
        canvas.drawRRect(bin, stroke);
        canvas.drawLine(Offset(p(0.18), p(0.28)), Offset(p(0.82), p(0.28)), stroke);
        canvas.drawLine(Offset(p(0.39), p(0.18)), Offset(p(0.61), p(0.18)), stroke);
        canvas.drawLine(Offset(p(0.43), p(0.45)), Offset(p(0.43), p(0.70)), stroke);
        canvas.drawLine(Offset(p(0.57), p(0.45)), Offset(p(0.57), p(0.70)), stroke);
      case GhstActionKind.save:
        final body = Path()
          ..moveTo(p(0.20), p(0.24))
          ..quadraticBezierTo(p(0.20), p(0.18), p(0.26), p(0.18))
          ..lineTo(p(0.68), p(0.18))
          ..lineTo(p(0.82), p(0.32))
          ..lineTo(p(0.82), p(0.76))
          ..quadraticBezierTo(p(0.82), p(0.82), p(0.76), p(0.82))
          ..lineTo(p(0.26), p(0.82))
          ..quadraticBezierTo(p(0.20), p(0.82), p(0.20), p(0.76))
          ..close();
        canvas.drawPath(body, fillSoft);
        canvas.drawPath(body, stroke);
        canvas.drawRect(Rect.fromLTRB(p(0.34), p(0.54), p(0.66), p(0.82)), stroke);
        canvas.drawLine(Offset(p(0.36), p(0.30)), Offset(p(0.60), p(0.30)), stroke);
      case GhstActionKind.send:
        final plane = Path()
          ..moveTo(p(0.16), p(0.46))
          ..lineTo(p(0.84), p(0.18))
          ..lineTo(p(0.58), p(0.84))
          ..lineTo(p(0.46), p(0.55))
          ..close();
        canvas.drawPath(plane, fillSoft);
        canvas.drawPath(plane, stroke);
        canvas.drawLine(Offset(p(0.46), p(0.55)), Offset(p(0.82), p(0.20)), stroke);
      case GhstActionKind.reply:
        final curve = Path()
          ..moveTo(p(0.42), p(0.26))
          ..lineTo(p(0.18), p(0.46))
          ..lineTo(p(0.42), p(0.66))
          ..moveTo(p(0.20), p(0.46))
          ..lineTo(p(0.58), p(0.46))
          ..quadraticBezierTo(p(0.82), p(0.46), p(0.82), p(0.74));
        canvas.drawPath(curve, stroke);
      case GhstActionKind.swap:
        canvas.drawLine(Offset(p(0.20), p(0.36)), Offset(p(0.78), p(0.36)), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(p(0.64), p(0.22))
            ..lineTo(p(0.80), p(0.36))
            ..lineTo(p(0.64), p(0.50)),
          stroke,
        );
        canvas.drawLine(Offset(p(0.80), p(0.66)), Offset(p(0.22), p(0.66)), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(p(0.36), p(0.52))
            ..lineTo(p(0.20), p(0.66))
            ..lineTo(p(0.36), p(0.80)),
          stroke,
        );
      case GhstActionKind.tune:
        for (final row in [(0.30, 0.36), (0.50, 0.66), (0.70, 0.44)]) {
          canvas.drawLine(Offset(p(0.16), p(row.$1)), Offset(p(0.84), p(row.$1)), stroke);
          canvas.drawCircle(Offset(p(row.$2), p(row.$1)), p(0.08), fillSoft);
          canvas.drawCircle(Offset(p(row.$2), p(row.$1)), p(0.08), stroke);
        }
      case GhstActionKind.layers:
        final top = Path()
          ..moveTo(p(0.50), p(0.18))
          ..lineTo(p(0.84), p(0.36))
          ..lineTo(p(0.50), p(0.54))
          ..lineTo(p(0.16), p(0.36))
          ..close();
        canvas.drawPath(top, fillSoft);
        canvas.drawPath(top, stroke);
        for (final dy in [0.15, 0.29]) {
          canvas.drawPath(
            Path()
              ..moveTo(p(0.18), p(0.36 + dy))
              ..lineTo(p(0.50), p(0.54 + dy))
              ..lineTo(p(0.82), p(0.36 + dy)),
            stroke,
          );
        }
      case GhstActionKind.fullscreen:
        final corners = Path()
          ..moveTo(p(0.18), p(0.36))
          ..lineTo(p(0.18), p(0.18))
          ..lineTo(p(0.36), p(0.18))
          ..moveTo(p(0.64), p(0.18))
          ..lineTo(p(0.82), p(0.18))
          ..lineTo(p(0.82), p(0.36))
          ..moveTo(p(0.82), p(0.64))
          ..lineTo(p(0.82), p(0.82))
          ..lineTo(p(0.64), p(0.82))
          ..moveTo(p(0.36), p(0.82))
          ..lineTo(p(0.18), p(0.82))
          ..lineTo(p(0.18), p(0.64));
        canvas.drawRect(Rect.fromLTRB(p(0.30), p(0.30), p(0.70), p(0.70)), fillSoft);
        canvas.drawPath(corners, stroke);
      case GhstActionKind.gps:
        canvas.drawCircle(c, p(0.28), fillSoft);
        canvas.drawCircle(c, p(0.28), stroke);
        canvas.drawCircle(c, p(0.09), fillSolid);
        canvas.drawLine(Offset(p(0.50), p(0.12)), Offset(p(0.50), p(0.22)), stroke);
        canvas.drawLine(Offset(p(0.50), p(0.78)), Offset(p(0.50), p(0.88)), stroke);
        canvas.drawLine(Offset(p(0.12), p(0.50)), Offset(p(0.22), p(0.50)), stroke);
        canvas.drawLine(Offset(p(0.78), p(0.50)), Offset(p(0.88), p(0.50)), stroke);
      case GhstActionKind.mapPin:
        final pin = Path()
          ..moveTo(p(0.50), p(0.86))
          ..quadraticBezierTo(p(0.20), p(0.58), p(0.22), p(0.39))
          ..arcToPoint(Offset(p(0.78), p(0.39)), radius: Radius.circular(p(0.28)))
          ..quadraticBezierTo(p(0.80), p(0.58), p(0.50), p(0.86));
        canvas.drawPath(pin, fillSoft);
        canvas.drawPath(pin, stroke);
        canvas.drawCircle(Offset(p(0.50), p(0.40)), p(0.10), stroke);
      case GhstActionKind.route:
        canvas.drawCircle(Offset(p(0.24), p(0.76)), p(0.09), fillSoft);
        canvas.drawCircle(Offset(p(0.24), p(0.76)), p(0.09), stroke);
        canvas.drawCircle(Offset(p(0.76), p(0.24)), p(0.09), fillSolid);
        final path = Path()
          ..moveTo(p(0.33), p(0.74))
          ..cubicTo(p(0.68), p(0.74), p(0.32), p(0.26), p(0.67), p(0.26));
        canvas.drawPath(path, stroke);
      case GhstActionKind.directions:
        final nav = Path()
          ..moveTo(p(0.50), p(0.14))
          ..lineTo(p(0.82), p(0.82))
          ..lineTo(p(0.50), p(0.67))
          ..lineTo(p(0.18), p(0.82))
          ..close();
        canvas.drawPath(nav, fillSoft);
        canvas.drawPath(nav, stroke);
      case GhstActionKind.phone:
        final handset = Path()
          ..moveTo(p(0.26), p(0.20))
          ..lineTo(p(0.38), p(0.20))
          ..lineTo(p(0.44), p(0.36))
          ..lineTo(p(0.35), p(0.45))
          ..quadraticBezierTo(p(0.43), p(0.59), p(0.55), p(0.65))
          ..lineTo(p(0.64), p(0.56))
          ..lineTo(p(0.80), p(0.62))
          ..lineTo(p(0.80), p(0.74))
          ..quadraticBezierTo(p(0.78), p(0.84), p(0.65), p(0.82))
          ..quadraticBezierTo(p(0.24), p(0.74), p(0.18), p(0.35))
          ..quadraticBezierTo(p(0.17), p(0.22), p(0.26), p(0.20));
        canvas.drawPath(handset, fillSoft);
        canvas.drawPath(handset, stroke);
      case GhstActionKind.chat:
        final bubble = Path()
          ..moveTo(p(0.24), p(0.22))
          ..lineTo(p(0.76), p(0.22))
          ..quadraticBezierTo(p(0.86), p(0.22), p(0.86), p(0.32))
          ..lineTo(p(0.86), p(0.62))
          ..quadraticBezierTo(p(0.86), p(0.72), p(0.76), p(0.72))
          ..lineTo(p(0.42), p(0.72))
          ..lineTo(p(0.22), p(0.84))
          ..lineTo(p(0.24), p(0.72))
          ..quadraticBezierTo(p(0.14), p(0.72), p(0.14), p(0.62))
          ..lineTo(p(0.14), p(0.32))
          ..quadraticBezierTo(p(0.14), p(0.22), p(0.24), p(0.22));
        canvas.drawPath(bubble, fillSoft);
        canvas.drawPath(bubble, stroke);
        for (final x in [0.35, 0.50, 0.65]) {
          canvas.drawCircle(Offset(p(x), p(0.47)), sw * 0.62, fillSolid);
        }
      case GhstActionKind.bell:
        final bell = Path()
          ..moveTo(p(0.22), p(0.68))
          ..quadraticBezierTo(p(0.28), p(0.58), p(0.28), p(0.42))
          ..arcToPoint(Offset(p(0.72), p(0.42)), radius: Radius.circular(p(0.22)))
          ..quadraticBezierTo(p(0.72), p(0.58), p(0.78), p(0.68))
          ..close();
        canvas.drawPath(bell, fillSoft);
        canvas.drawPath(bell, stroke);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(p(0.50), p(0.72)), radius: p(0.09)),
          0,
          math.pi,
          false,
          stroke,
        );
      case GhstActionKind.cart:
        final basket = Path()
          ..moveTo(p(0.14), p(0.22))
          ..lineTo(p(0.25), p(0.22))
          ..lineTo(p(0.34), p(0.62))
          ..lineTo(p(0.76), p(0.62))
          ..lineTo(p(0.85), p(0.32))
          ..lineTo(p(0.28), p(0.32));
        canvas.drawPolygonLike(
          [
            Offset(p(0.28), p(0.32)),
            Offset(p(0.85), p(0.32)),
            Offset(p(0.76), p(0.62)),
            Offset(p(0.34), p(0.62)),
          ],
          fillSoft,
        );
        canvas.drawPath(basket, stroke);
        canvas.drawCircle(Offset(p(0.40), p(0.77)), p(0.065), stroke);
        canvas.drawCircle(Offset(p(0.71), p(0.77)), p(0.065), stroke);
      case GhstActionKind.bag:
        final bag = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.22), p(0.34), p(0.78), p(0.84)),
          Radius.circular(p(0.09)),
        );
        canvas.drawRRect(bag, fillSoft);
        canvas.drawRRect(bag, stroke);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(p(0.50), p(0.34)), radius: p(0.15)),
          math.pi,
          math.pi,
          false,
          stroke,
        );
      case GhstActionKind.store:
        final base = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.20), p(0.44), p(0.80), p(0.84)),
          Radius.circular(p(0.06)),
        );
        canvas.drawRRect(base, fillSoft);
        canvas.drawRRect(base, stroke);
        final awning = Path()
          ..moveTo(p(0.15), p(0.44))
          ..lineTo(p(0.24), p(0.20))
          ..lineTo(p(0.76), p(0.20))
          ..lineTo(p(0.85), p(0.44))
          ..close();
        canvas.drawPath(awning, fillSoft);
        canvas.drawPath(awning, stroke);
        canvas.drawLine(Offset(p(0.50), p(0.62)), Offset(p(0.50), p(0.84)), stroke);
      case GhstActionKind.food:
        final bowl = Path()
          ..moveTo(p(0.16), p(0.50))
          ..lineTo(p(0.84), p(0.50))
          ..arcToPoint(Offset(p(0.16), p(0.50)), radius: Radius.circular(p(0.34)));
        canvas.drawPath(bowl, fillSoft);
        canvas.drawPath(bowl, stroke);
        canvas.drawLine(Offset(p(0.36), p(0.22)), Offset(p(0.36), p(0.38)), stroke);
        canvas.drawLine(Offset(p(0.52), p(0.18)), Offset(p(0.52), p(0.38)), stroke);
        canvas.drawLine(Offset(p(0.66), p(0.22)), Offset(p(0.66), p(0.38)), stroke);
      case GhstActionKind.box:
        final cube = Path()
          ..moveTo(p(0.50), p(0.15))
          ..lineTo(p(0.83), p(0.33))
          ..lineTo(p(0.83), p(0.69))
          ..lineTo(p(0.50), p(0.86))
          ..lineTo(p(0.17), p(0.69))
          ..lineTo(p(0.17), p(0.33))
          ..close();
        canvas.drawPath(cube, fillSoft);
        canvas.drawPath(cube, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(p(0.17), p(0.33))
            ..lineTo(p(0.50), p(0.51))
            ..lineTo(p(0.83), p(0.33))
            ..moveTo(p(0.50), p(0.51))
            ..lineTo(p(0.50), p(0.86)),
          stroke,
        );
      case GhstActionKind.scooter:
        canvas.drawCircle(Offset(p(0.26), p(0.72)), p(0.12), fillSoft);
        canvas.drawCircle(Offset(p(0.74), p(0.72)), p(0.12), fillSoft);
        canvas.drawCircle(Offset(p(0.26), p(0.72)), p(0.12), stroke);
        canvas.drawCircle(Offset(p(0.74), p(0.72)), p(0.12), stroke);
        final chassis = Path()
          ..moveTo(p(0.26), p(0.72))
          ..lineTo(p(0.46), p(0.72))
          ..lineTo(p(0.58), p(0.44))
          ..lineTo(p(0.70), p(0.44))
          ..lineTo(p(0.74), p(0.72))
          ..moveTo(p(0.56), p(0.30))
          ..lineTo(p(0.70), p(0.30))
          ..moveTo(p(0.20), p(0.44))
          ..lineTo(p(0.40), p(0.44))
          ..lineTo(p(0.40), p(0.58))
          ..lineTo(p(0.20), p(0.58))
          ..close();
        canvas.drawPath(chassis, stroke);
      case GhstActionKind.truck:
        final cargo = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.12), p(0.26), p(0.60), p(0.68)),
          Radius.circular(p(0.06)),
        );
        canvas.drawRRect(cargo, fillSoft);
        canvas.drawRRect(cargo, stroke);
        final cab = Path()
          ..moveTo(p(0.60), p(0.38))
          ..lineTo(p(0.76), p(0.38))
          ..lineTo(p(0.88), p(0.53))
          ..lineTo(p(0.88), p(0.68))
          ..lineTo(p(0.60), p(0.68));
        canvas.drawPath(cab, stroke);
        canvas.drawCircle(Offset(p(0.30), p(0.74)), p(0.08), stroke);
        canvas.drawCircle(Offset(p(0.73), p(0.74)), p(0.08), stroke);
      case GhstActionKind.hub:
        canvas.drawCircle(c, p(0.13), fillSoft);
        canvas.drawCircle(c, p(0.13), stroke);
        for (final pt in [
          Offset(p(0.22), p(0.24)),
          Offset(p(0.78), p(0.24)),
          Offset(p(0.22), p(0.76)),
          Offset(p(0.78), p(0.76)),
        ]) {
          final dir = (pt - c);
          final start = c + dir * 0.42;
          final end = c + dir * 0.72;
          canvas.drawLine(start, end, stroke);
          canvas.drawCircle(pt, p(0.075), fillSoft);
          canvas.drawCircle(pt, p(0.075), stroke);
        }
      case GhstActionKind.wallet:
        final body = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.15), p(0.26), p(0.85), p(0.78)),
          Radius.circular(p(0.10)),
        );
        canvas.drawRRect(body, fillSoft);
        canvas.drawRRect(body, stroke);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(p(0.58), p(0.43), p(0.86), p(0.61)),
            Radius.circular(p(0.07)),
          ),
          stroke,
        );
        canvas.drawCircle(Offset(p(0.68), p(0.52)), sw * 0.6, fillSolid);
      case GhstActionKind.voucher:
        final ticket = Path()
          ..moveTo(p(0.16), p(0.28))
          ..lineTo(p(0.84), p(0.28))
          ..lineTo(p(0.84), p(0.43))
          ..arcToPoint(Offset(p(0.84), p(0.57)), radius: Radius.circular(p(0.07)), clockwise: false)
          ..lineTo(p(0.84), p(0.72))
          ..lineTo(p(0.16), p(0.72))
          ..lineTo(p(0.16), p(0.57))
          ..arcToPoint(Offset(p(0.16), p(0.43)), radius: Radius.circular(p(0.07)), clockwise: false)
          ..close();
        canvas.drawPath(ticket, fillSoft);
        canvas.drawPath(ticket, stroke);
        canvas.drawLine(Offset(p(0.44), p(0.35)), Offset(p(0.44), p(0.65)), stroke);
      case GhstActionKind.bolt:
        final bolt = Path()
          ..moveTo(p(0.56), p(0.14))
          ..lineTo(p(0.24), p(0.54))
          ..lineTo(p(0.48), p(0.54))
          ..lineTo(p(0.42), p(0.86))
          ..lineTo(p(0.76), p(0.45))
          ..lineTo(p(0.52), p(0.45))
          ..close();
        canvas.drawPath(bolt, fillSoft);
        canvas.drawPath(bolt, stroke);
      case GhstActionKind.gift:
        final box = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.20), p(0.42), p(0.80), p(0.84)),
          Radius.circular(p(0.07)),
        );
        canvas.drawRRect(box, fillSoft);
        canvas.drawRRect(box, stroke);
        canvas.drawRect(Rect.fromLTRB(p(0.16), p(0.30), p(0.84), p(0.42)), stroke);
        canvas.drawLine(Offset(p(0.50), p(0.30)), Offset(p(0.50), p(0.84)), stroke);
        canvas.drawCircle(Offset(p(0.41), p(0.23)), p(0.07), stroke);
        canvas.drawCircle(Offset(p(0.59), p(0.23)), p(0.07), stroke);
      case GhstActionKind.wheel:
        canvas.drawCircle(c, p(0.36), fillSoft);
        canvas.drawCircle(c, p(0.36), stroke);
        canvas.drawCircle(c, p(0.09), fillSolid);
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3.0;
          canvas.drawLine(
            c + Offset(math.cos(a), math.sin(a)) * p(0.09),
            c + Offset(math.cos(a), math.sin(a)) * p(0.36),
            stroke,
          );
        }
      case GhstActionKind.sparkle:
        final star = Path()
          ..moveTo(p(0.50), p(0.14))
          ..quadraticBezierTo(p(0.53), p(0.47), p(0.86), p(0.50))
          ..quadraticBezierTo(p(0.53), p(0.53), p(0.50), p(0.86))
          ..quadraticBezierTo(p(0.47), p(0.53), p(0.14), p(0.50))
          ..quadraticBezierTo(p(0.47), p(0.47), p(0.50), p(0.14));
        canvas.drawPath(star, fillSoft);
        canvas.drawPath(star, stroke);
        canvas.drawCircle(Offset(p(0.77), p(0.23)), sw * 0.55, fillSolid);
      case GhstActionKind.upload:
      case GhstActionKind.download:
        final tray = Path()
          ..moveTo(p(0.18), p(0.64))
          ..lineTo(p(0.18), p(0.78))
          ..quadraticBezierTo(p(0.18), p(0.84), p(0.24), p(0.84))
          ..lineTo(p(0.76), p(0.84))
          ..quadraticBezierTo(p(0.82), p(0.84), p(0.82), p(0.78))
          ..lineTo(p(0.82), p(0.64));
        canvas.drawPath(tray, stroke);
        canvas.drawLine(Offset(p(0.50), p(0.20)), Offset(p(0.50), p(0.66)), stroke);
        if (kind == GhstActionKind.upload) {
          canvas.drawPath(
            Path()
              ..moveTo(p(0.34), p(0.36))
              ..lineTo(p(0.50), p(0.19))
              ..lineTo(p(0.66), p(0.36)),
            stroke,
          );
        } else {
          canvas.drawPath(
            Path()
              ..moveTo(p(0.34), p(0.50))
              ..lineTo(p(0.50), p(0.67))
              ..lineTo(p(0.66), p(0.50)),
            stroke,
          );
        }
      case GhstActionKind.camera:
        final cam = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.14), p(0.30), p(0.86), p(0.78)),
          Radius.circular(p(0.10)),
        );
        canvas.drawRRect(cam, fillSoft);
        canvas.drawRRect(cam, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(p(0.34), p(0.30))
            ..lineTo(p(0.40), p(0.20))
            ..lineTo(p(0.60), p(0.20))
            ..lineTo(p(0.66), p(0.30)),
          stroke,
        );
        canvas.drawCircle(Offset(p(0.50), p(0.55)), p(0.13), stroke);
      case GhstActionKind.image:
        final frame = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.16), p(0.20), p(0.84), p(0.80)),
          Radius.circular(p(0.10)),
        );
        canvas.drawRRect(frame, fillSoft);
        canvas.drawRRect(frame, stroke);
        canvas.drawCircle(Offset(p(0.35), p(0.38)), p(0.06), fillSolid);
        canvas.drawPath(
          Path()
            ..moveTo(p(0.20), p(0.74))
            ..lineTo(p(0.44), p(0.50))
            ..lineTo(p(0.58), p(0.63))
            ..lineTo(p(0.70), p(0.52))
            ..lineTo(p(0.82), p(0.68)),
          stroke,
        );
      case GhstActionKind.qr:
      case GhstActionKind.scanner:
        for (final pos in [
          Rect.fromLTWH(p(0.18), p(0.18), p(0.24), p(0.24)),
          Rect.fromLTWH(p(0.58), p(0.18), p(0.24), p(0.24)),
          Rect.fromLTWH(p(0.18), p(0.58), p(0.24), p(0.24)),
        ]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(pos, Radius.circular(p(0.04))),
            fillSoft,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(pos, Radius.circular(p(0.04))),
            stroke,
          );
        }
        canvas.drawRect(Rect.fromLTWH(p(0.60), p(0.60), p(0.10), p(0.10)), fillSolid);
        canvas.drawRect(Rect.fromLTWH(p(0.72), p(0.72), p(0.10), p(0.10)), fillSolid);
        if (kind == GhstActionKind.scanner) {
          canvas.drawLine(Offset(p(0.12), p(0.50)), Offset(p(0.88), p(0.50)), stroke);
        }
      case GhstActionKind.print:
        canvas.drawRect(Rect.fromLTRB(p(0.30), p(0.18), p(0.70), p(0.36)), stroke);
        final body = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.16), p(0.36), p(0.84), p(0.68)),
          Radius.circular(p(0.08)),
        );
        canvas.drawRRect(body, fillSoft);
        canvas.drawRRect(body, stroke);
        canvas.drawRect(Rect.fromLTRB(p(0.30), p(0.58), p(0.70), p(0.84)), stroke);
      case GhstActionKind.link:
      case GhstActionKind.unlink:
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-math.pi / 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(-p(0.34), -p(0.13), -p(0.02), p(0.13)),
            Radius.circular(p(0.13)),
          ),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(p(0.02), -p(0.13), p(0.34), p(0.13)),
            Radius.circular(p(0.13)),
          ),
          stroke,
        );
        if (kind == GhstActionKind.link) {
          canvas.drawLine(Offset(-p(0.12), 0), Offset(p(0.12), 0), stroke);
        }
        canvas.restore();
        if (kind == GhstActionKind.unlink) {
          canvas.drawLine(Offset(p(0.22), p(0.22)), Offset(p(0.78), p(0.78)), stroke);
        }
      case GhstActionKind.calendar:
        final cal = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.16), p(0.24), p(0.84), p(0.84)),
          Radius.circular(p(0.09)),
        );
        canvas.drawRRect(cal, fillSoft);
        canvas.drawRRect(cal, stroke);
        canvas.drawLine(Offset(p(0.16), p(0.41)), Offset(p(0.84), p(0.41)), stroke);
        canvas.drawLine(Offset(p(0.34), p(0.15)), Offset(p(0.34), p(0.30)), stroke);
        canvas.drawLine(Offset(p(0.66), p(0.15)), Offset(p(0.66), p(0.30)), stroke);
      case GhstActionKind.clock:
        canvas.drawCircle(c, p(0.36), fillSoft);
        canvas.drawCircle(c, p(0.36), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(p(0.50), p(0.30))
            ..lineTo(p(0.50), p(0.52))
            ..lineTo(p(0.66), p(0.61)),
          stroke,
        );
      case GhstActionKind.chart:
        canvas.drawLine(Offset(p(0.16), p(0.82)), Offset(p(0.84), p(0.82)), stroke);
        for (final bar in [(0.26, 0.56), (0.50, 0.40), (0.74, 0.24)]) {
          final r = RRect.fromRectAndRadius(
            Rect.fromLTRB(p(bar.$1 - 0.07), p(bar.$2), p(bar.$1 + 0.07), p(0.82)),
            Radius.circular(p(0.04)),
          );
          canvas.drawRRect(r, fillSoft);
          canvas.drawRRect(r, stroke);
        }
      case GhstActionKind.grid:
        for (final x in [0.18, 0.54]) {
          for (final y in [0.18, 0.54]) {
            final cell = RRect.fromRectAndRadius(
              Rect.fromLTWH(p(x), p(y), p(0.28), p(0.28)),
              Radius.circular(p(0.06)),
            );
            canvas.drawRRect(cell, fillSoft);
            canvas.drawRRect(cell, stroke);
          }
        }
      case GhstActionKind.receipt:
        final doc = RRect.fromRectAndRadius(
          Rect.fromLTRB(p(0.22), p(0.16), p(0.78), p(0.84)),
          Radius.circular(p(0.08)),
        );
        canvas.drawRRect(doc, fillSoft);
        canvas.drawRRect(doc, stroke);
        canvas.drawLine(Offset(p(0.34), p(0.36)), Offset(p(0.66), p(0.36)), stroke);
        canvas.drawLine(Offset(p(0.34), p(0.52)), Offset(p(0.66), p(0.52)), stroke);
        canvas.drawLine(Offset(p(0.34), p(0.68)), Offset(p(0.54), p(0.68)), stroke);
      case GhstActionKind.star:
        final star = Path();
        for (var i = 0; i < 10; i++) {
          final r = i.isEven ? p(0.38) : p(0.17);
          final a = -math.pi / 2 + i * math.pi / 5;
          final pt = c + Offset(math.cos(a) * r, math.sin(a) * r);
          if (i == 0) {
            star.moveTo(pt.dx, pt.dy);
          } else {
            star.lineTo(pt.dx, pt.dy);
          }
        }
        star.close();
        canvas.drawPath(star, fillSoft);
        canvas.drawPath(star, stroke);
      case GhstActionKind.heart:
        final heart = Path()
          ..moveTo(p(0.50), p(0.82))
          ..cubicTo(p(0.14), p(0.58), p(0.14), p(0.24), p(0.35), p(0.24))
          ..quadraticBezierTo(p(0.46), p(0.24), p(0.50), p(0.35))
          ..quadraticBezierTo(p(0.54), p(0.24), p(0.65), p(0.24))
          ..cubicTo(p(0.86), p(0.24), p(0.86), p(0.58), p(0.50), p(0.82));
        canvas.drawPath(heart, fillSoft);
        canvas.drawPath(heart, stroke);
      case GhstActionKind.bookmark:
        final bm = Path()
          ..moveTo(p(0.26), p(0.18))
          ..lineTo(p(0.74), p(0.18))
          ..lineTo(p(0.74), p(0.84))
          ..lineTo(p(0.50), p(0.68))
          ..lineTo(p(0.26), p(0.84))
          ..close();
        canvas.drawPath(bm, fillSoft);
        canvas.drawPath(bm, stroke);
      case GhstActionKind.flag:
        canvas.drawLine(Offset(p(0.24), p(0.16)), Offset(p(0.24), p(0.86)), stroke);
        final banner = Path()
          ..moveTo(p(0.24), p(0.20))
          ..lineTo(p(0.78), p(0.26))
          ..lineTo(p(0.68), p(0.42))
          ..lineTo(p(0.78), p(0.58))
          ..lineTo(p(0.24), p(0.56))
          ..close();
        canvas.drawPath(banner, fillSoft);
        canvas.drawPath(banner, stroke);
      case GhstActionKind.sun:
        canvas.drawCircle(c, p(0.19), fillSoft);
        canvas.drawCircle(c, p(0.19), stroke);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawLine(
            c + Offset(math.cos(a), math.sin(a)) * p(0.27),
            c + Offset(math.cos(a), math.sin(a)) * p(0.39),
            stroke,
          );
        }
      case GhstActionKind.moon:
        final moon = Path()
          ..moveTo(p(0.62), p(0.18))
          ..arcToPoint(
            Offset(p(0.82), p(0.66)),
            radius: Radius.circular(p(0.34)),
            clockwise: false,
          )
          ..arcToPoint(
            Offset(p(0.62), p(0.18)),
            radius: Radius.circular(p(0.26)),
          );
        canvas.drawPath(moon, fillSoft);
        canvas.drawPath(moon, stroke);
      case GhstActionKind.autoTheme:
        canvas.drawCircle(c, p(0.34), stroke);
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: p(0.34)),
          -math.pi / 2,
          math.pi,
          true,
          fillSoft,
        );
        canvas.drawCircle(Offset(p(0.76), p(0.22)), sw * 0.65, fillSolid);
      case GhstActionKind.gear:
        canvas.drawCircle(c, p(0.26), fillSoft);
        canvas.drawCircle(c, p(0.26), stroke);
        canvas.drawCircle(c, p(0.11), stroke);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawLine(
            c + Offset(math.cos(a), math.sin(a)) * p(0.26),
            c + Offset(math.cos(a), math.sin(a)) * p(0.38),
            stroke,
          );
        }
      case GhstActionKind.cloudSync:
      case GhstActionKind.cloudOff:
        final cloud = Path()
          ..moveTo(p(0.28), p(0.72))
          ..lineTo(p(0.73), p(0.72))
          ..arcToPoint(Offset(p(0.72), p(0.44)), radius: Radius.circular(p(0.15)), clockwise: false)
          ..arcToPoint(Offset(p(0.34), p(0.39)), radius: Radius.circular(p(0.21)), clockwise: false)
          ..arcToPoint(Offset(p(0.28), p(0.72)), radius: Radius.circular(p(0.16)), clockwise: false);
        canvas.drawPath(cloud, fillSoft);
        canvas.drawPath(cloud, stroke);
        if (kind == GhstActionKind.cloudOff) {
          canvas.drawLine(Offset(p(0.20), p(0.20)), Offset(p(0.80), p(0.80)), stroke);
        }
      case GhstActionKind.play:
        final tri = Path()
          ..moveTo(p(0.30), p(0.22))
          ..lineTo(p(0.78), p(0.50))
          ..lineTo(p(0.30), p(0.78))
          ..close();
        canvas.drawPath(tri, fillSoft);
        canvas.drawPath(tri, stroke);
      case GhstActionKind.pause:
        canvas.drawCircle(c, p(0.37), fillSoft);
        canvas.drawCircle(c, p(0.37), stroke);
        canvas.drawLine(Offset(p(0.41), p(0.35)), Offset(p(0.41), p(0.65)), stroke);
        canvas.drawLine(Offset(p(0.59), p(0.35)), Offset(p(0.59), p(0.65)), stroke);
      case GhstActionKind.warning:
        final tri = Path()
          ..moveTo(p(0.50), p(0.16))
          ..lineTo(p(0.86), p(0.80))
          ..lineTo(p(0.14), p(0.80))
          ..close();
        canvas.drawPath(tri, fillSoft);
        canvas.drawPath(tri, stroke);
        canvas.drawLine(Offset(p(0.50), p(0.40)), Offset(p(0.50), p(0.58)), stroke);
        canvas.drawCircle(Offset(p(0.50), p(0.70)), sw * 0.62, fillSolid);
      case GhstActionKind.info:
        canvas.drawCircle(c, p(0.37), fillSoft);
        canvas.drawCircle(c, p(0.37), stroke);
        canvas.drawLine(Offset(p(0.50), p(0.46)), Offset(p(0.50), p(0.69)), stroke);
        canvas.drawCircle(Offset(p(0.50), p(0.33)), sw * 0.65, fillSolid);
      case GhstActionKind.weather:
        final cloud = Path()
          ..moveTo(p(0.26), p(0.58))
          ..lineTo(p(0.74), p(0.58))
          ..arcToPoint(Offset(p(0.72), p(0.34)), radius: Radius.circular(p(0.13)), clockwise: false)
          ..arcToPoint(Offset(p(0.34), p(0.30)), radius: Radius.circular(p(0.19)), clockwise: false)
          ..arcToPoint(Offset(p(0.26), p(0.58)), radius: Radius.circular(p(0.14)), clockwise: false);
        canvas.drawPath(cloud, fillSoft);
        canvas.drawPath(cloud, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(p(0.52), p(0.58))
            ..lineTo(p(0.43), p(0.73))
            ..lineTo(p(0.55), p(0.73))
            ..lineTo(p(0.47), p(0.88)),
          stroke,
        );
      case GhstActionKind.eco:
        final leaf = Path()
          ..moveTo(p(0.22), p(0.78))
          ..quadraticBezierTo(p(0.20), p(0.24), p(0.80), p(0.20))
          ..quadraticBezierTo(p(0.78), p(0.80), p(0.22), p(0.78));
        canvas.drawPath(leaf, fillSoft);
        canvas.drawPath(leaf, stroke);
        canvas.drawLine(Offset(p(0.22), p(0.78)), Offset(p(0.62), p(0.38)), stroke);
      case GhstActionKind.radioOn:
        canvas.drawCircle(c, p(0.36), stroke);
        canvas.drawCircle(c, p(0.18), fillSolid);
      case GhstActionKind.radioOff:
        canvas.drawCircle(c, p(0.36), stroke);
      case GhstActionKind.dot:
        canvas.drawCircle(c, p(0.22), fillSolid);
    }
  }

  void _paintGoogleEmblem(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width * 0.5, size.height * 0.5);
    canvas.drawCircle(
      c,
      s * 0.47,
      Paint()
        ..isAntiAlias = true
        ..color = Colors.white,
    );
    canvas.drawCircle(
      c,
      s * 0.47,
      Paint()
        ..isAntiAlias = true
        ..color = const Color(0xFFD8E2F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (s * 0.05).clamp(0.8, 1.4),
    );

    final sw = (s * 0.135).clamp(1.8, 3.6);
    final rect = Rect.fromCircle(center: c, radius: s * 0.27);
    Paint seg(Color col) => Paint()
      ..isAntiAlias = true
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(rect, -math.pi * 0.78, math.pi * 0.55, false, seg(const Color(0xFFEA4335)));
    canvas.drawArc(rect, math.pi * 0.76, math.pi * 0.48, false, seg(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, math.pi * 0.22, math.pi * 0.56, false, seg(const Color(0xFF34A853)));
    canvas.drawArc(rect, -math.pi * 0.04, math.pi * 0.28, false, seg(const Color(0xFF4285F4)));
    canvas.drawLine(
      Offset(c.dx + s * 0.01, c.dy),
      Offset(c.dx + s * 0.32, c.dy),
      Paint()
        ..isAntiAlias = true
        ..color = const Color(0xFF4285F4)
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _GhstActionGlyphPainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.color != color ||
        oldDelegate.selected != selected;
  }
}

extension on Canvas {
  void drawPolygonLike(List<Offset> pts, Paint paint) {
    if (pts.length < 3) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    drawPath(path, paint);
  }
}
