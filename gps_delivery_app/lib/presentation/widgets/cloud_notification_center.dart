import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/integrations/push_notification_service.dart';
import '../../core/network/public_json_api.dart';
import '../screens/cloud_pickup_screen.dart';
import '../screens/cloud_promo_events_screen.dart';
import '../screens/market_order_services_screen.dart';
import '../screens/marketplace_view.dart';
import 'cloud_order_labels.dart';
import 'cloud_session_boundary.dart';
import 'ghst_button_icon.dart';

Future<void> openCloudNotificationCenter(
  BuildContext context,
  CloudAccountSession session, {
  bool operator = false,
  ValueChanged<String>? onOpenShippingOrder,
  ValueChanged<String?>? onOpenMarketOrder,
  VoidCallback? onOpenPickup,
  VoidCallback? onOpenPromo,
  VoidCallback? onOpenProfile,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CloudSessionBoundary(
      session: session,
      operator: operator,
      builder: (_, lease) => Scaffold(
        appBar: AppBar(title: const Text('Trung tâm thông báo')),
        body: SafeArea(
          child: CloudNotificationCenter(
            session: session,
            lease: lease,
            operator: operator,
            onOpenShippingOrder: onOpenShippingOrder,
            onOpenMarketOrder: onOpenMarketOrder,
            onOpenPickup: onOpenPickup,
            onOpenPromo: onOpenPromo,
            onOpenProfile: onOpenProfile,
          ),
        ),
      ),
    ),
  ),
);

class CloudNotificationCenter extends StatefulWidget {
  const CloudNotificationCenter({
    super.key,
    required this.session,
    this.lease,
    this.embedded = false,
    this.operator = false,
    this.onOpenShippingOrder,
    this.onOpenMarketOrder,
    this.onOpenPickup,
    this.onOpenPromo,
    this.onOpenProfile,
  });

  final CloudAccountSession session;
  final CloudSessionLease? lease;
  final bool embedded;
  final bool operator;
  final ValueChanged<String>? onOpenShippingOrder;
  final ValueChanged<String?>? onOpenMarketOrder;
  final VoidCallback? onOpenPickup;
  final VoidCallback? onOpenPromo;
  final VoidCallback? onOpenProfile;

  @override
  State<CloudNotificationCenter> createState() =>
      _CloudNotificationCenterState();
}

class _CloudNotificationCenterState extends State<CloudNotificationCenter> {
  static const Map<String, String> _categories = {
    'all': 'Tất cả',
    'shipping': 'Vận chuyển',
    'market': 'Mua sắm',
    'promo': 'Khuyến mãi',
    'account': 'Tài khoản',
  };

  StreamSubscription<Map<String, dynamic>>? _incomingSub;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic>? _nextCursor;
  String _category = 'all';
  bool _unreadOnly = false;
  bool _showSettings = false;
  bool _busy = false;
  bool _loadingMore = false;
  bool _savingPref = false;
  int _unreadCount = 0;
  String? _error;

  bool get _valid =>
      widget.session.canUseBusiness && (widget.lease?.valid ?? true);

  @override
  void initState() {
    super.initState();
    _unreadCount = PushNotificationService.instance.unreadCount;
    _incomingSub = PushNotificationService.instance.incomingAlerts.listen((_) {
      if (mounted && _valid && !_busy) {
        unawaited(_load());
      }
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_incomingSub?.cancel());
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(dynamic raw) => (raw as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  Future<void> _load({bool append = false}) async {
    if (!_valid) return;
    if (append ? (_loadingMore || _nextCursor == null) : _busy) return;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _busy = true;
      }
      _error = null;
    });
    try {
      final res = await widget.session.service.notifications('list', {
        'category': _category,
        'unread_only': _unreadOnly,
        'limit': 30,
        if (append && _nextCursor != null) ..._nextCursor!,
      });
      if (!mounted || !_valid) return;
      final fetched = _rows(res['notifications'] ?? res['items']);
      final unread = (res['unread_count'] as num? ?? _unreadCount).toInt();
      final nextRaw = res['next'];
      PushNotificationService.instance.applyUnreadCount(unread);
      PushNotificationService.instance.applyPreferences(res['preferences']);
      setState(() {
        _items = append ? [..._items, ...fetched] : fetched;
        _unreadCount = unread < 0 ? 0 : unread;
        _nextCursor = nextRaw is Map
            ? Map<String, dynamic>.from(nextRaw)
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      if (widget.lease?.handleAccessFailure(e) == true) return;
      setState(() {
        _error = e is PublicApiException && e.statusCode != 503
            ? e.message
            : e is PublicApiException && e.statusCode == 503
            ? 'Dịch vụ tạm thời chưa khả dụng. Vui lòng thử lại sau.'
            : 'Chưa tải được danh sách thông báo.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _markAllRead() async {
    if (_busy || !_valid || _unreadCount <= 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.session.service.notifications('mark_all_read', {
        'category': _category,
      });
      if (!mounted || !_valid) return;
      final unread = (res['unread_count'] as num? ?? 0).toInt();
      final nowIso = DateTime.now().toUtc().toIso8601String();
      PushNotificationService.instance.applyUnreadCount(unread);
      setState(() {
        _unreadCount = unread < 0 ? 0 : unread;
        if (_unreadOnly) {
          _items = const [];
          _nextCursor = null;
        } else {
          _items = _items
              .map(
                (n) => n['read_at'] == null ? {...n, 'read_at': nowIso} : n,
              )
              .toList();
        }
      });
    } catch (e) {
      if (mounted && widget.lease?.handleAccessFailure(e) != true) {
        setState(() {
          _error = e is PublicApiException
              ? e.message
              : 'Không đánh dấu đã đọc được.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tapItem(Map<String, dynamic> item) async {
    if (!_valid) return;
    final id = '${item['id'] ?? ''}'.trim();
    if (id.isNotEmpty && item['read_at'] == null) {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      setState(() {
        _items = _unreadOnly
            ? _items.where((e) => '${e['id']}' != id).toList()
            : _items
                  .map(
                    (e) => '${e['id']}' == id ? {...e, 'read_at': nowIso} : e,
                  )
                  .toList();
        if (_unreadCount > 0) _unreadCount--;
      });
      PushNotificationService.instance.applyUnreadCount(_unreadCount);
      try {
        final res = await widget.session.service.notifications('mark_read', {
          'id': id,
        });
        if (mounted && _valid) {
          final unread = (res['unread_count'] as num? ?? _unreadCount).toInt();
          _unreadCount = unread < 0 ? 0 : unread;
          PushNotificationService.instance.applyUnreadCount(_unreadCount);
          setState(() {});
        }
      } catch (_) {}
    }

    if (!mounted || !_valid) return;
    final category = '${item['category'] ?? ''}';
    final kind = '${item['kind'] ?? ''}';
    final refType = '${item['reference_type'] ?? item['ref_type'] ?? ''}';
    final refId = '${item['reference_id'] ?? item['ref_id'] ?? ''}'.trim();

    if (refType == 'pickup' || kind.startsWith('pickup_')) {
      if (widget.onOpenPickup != null) {
        widget.onOpenPickup!();
      } else {
        await openCloudPickups(
          context,
          widget.session,
          operator: widget.operator,
        );
      }
      return;
    }

    if (refType == 'cloud_order' ||
        refType == 'shipping_order' ||
        category == 'shipping') {
      if (widget.onOpenShippingOrder != null && refId.isNotEmpty) {
        widget.onOpenShippingOrder!(refId);
      }
      return;
    }

    if (refType == 'market_order' || category == 'market') {
      if ((kind == 'message' || kind == 'market_message') && refId.isNotEmpty) {
        await openMarketOrderConversation(context, widget.session, refId);
        return;
      }
      if (widget.onOpenMarketOrder != null) {
        widget.onOpenMarketOrder!(refId.isEmpty ? null : refId);
      } else {
        await openMarketOrderServices(
          context,
          widget.session,
          orderId: refId.isEmpty ? null : refId,
          operator: widget.operator,
        );
      }
      return;
    }

    if (category == 'promo') {
      if (widget.onOpenPromo != null) {
        widget.onOpenPromo!();
      } else {
        await openCloudPromoEvents(context, widget.session);
      }
      return;
    }

    if (category == 'account') {
      widget.onOpenProfile?.call();
    }
  }

  Future<void> _togglePreference(String key, bool value) async {
    if (_savingPref || !_valid) return;
    setState(() {
      _savingPref = true;
      _error = null;
    });
    try {
      await PushNotificationService.instance.updatePreferences(
        {key: value},
        session: widget.session,
      );
    } catch (e) {
      if (mounted && widget.lease?.handleAccessFailure(e) != true) {
        setState(() {
          _error = e is PublicApiException
              ? e.message
              : e is StateError
              ? e.message
              : 'Không lưu được tùy chọn thông báo.';
        });
      }
    } finally {
      if (mounted) setState(() => _savingPref = false);
    }
  }

  IconData _iconFor(String category, String kind) {
    if (kind.contains('coin') ||
        kind.contains('promo') ||
        kind.contains('shipping_cancel') ||
        kind == 'earn_shipping') {
      return Icons.monetization_on_outlined;
    }
    return switch (category) {
      'shipping' => Icons.local_shipping_outlined,
      'market' => Icons.storefront_outlined,
      'promo' => Icons.card_giftcard_outlined,
      'account' => Icons.verified_user_outlined,
      _ => Icons.notifications_outlined,
    };
  }

  Color _accentFor(String category, ThemeData theme) {
    return switch (category) {
      'shipping' => const Color(0xFF0284C7),
      'market' => const Color(0xFF059669),
      'promo' => const Color(0xFFD97706),
      'account' => const Color(0xFF7C3AED),
      _ => theme.colorScheme.primary,
    };
  }

  Widget _buildPreferencesCard(ThemeData theme) {
    return ListenableBuilder(
      listenable: PushNotificationService.instance,
      builder: (context, _) {
        final prefs = PushNotificationService.instance.preferences;
        final devicePushOn =
            PushNotificationService.instance.enabled &&
            prefs['push_enabled'] != false;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (PushNotificationService.supported)
                  SwitchListTile(
                    dense: true,
                    value: devicePushOn,
                    onChanged: _savingPref
                        ? null
                        : (v) => _togglePreference('push_enabled', v),
                    secondary: const GhstButtonIcon(Icons.notifications_active_outlined),
                    title: const Text(
                      'Thông báo đẩy trên thiết bị',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      devicePushOn
                          ? 'Hiển thị thông báo hệ thống ngay khi có cập nhật mới'
                          : 'Bật để nhận cảnh báo tức thời trên thiết bị này',
                    ),
                  ),
                SwitchListTile(
                  dense: true,
                  value: prefs['shipping_updates'] != false,
                  onChanged: _savingPref
                      ? null
                      : (v) => _togglePreference('shipping_updates', v),
                  secondary: const GhstButtonIcon(Icons.local_shipping_outlined),
                  title: const Text('Cập nhật vận đơn & thu gom'),
                  subtitle: const Text(
                    'Trạng thái nhận chuyến, đang giao, hoàn tất và điều xe',
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  value: prefs['market_updates'] != false,
                  onChanged: _savingPref
                      ? null
                      : (v) => _togglePreference('market_updates', v),
                  secondary: const GhstButtonIcon(Icons.storefront_outlined),
                  title: const Text('Đơn mua sắm & gian hàng'),
                  subtitle: const Text(
                    'Xác nhận đơn ăn uống, hậu mãi hoàn tiền và quyết toán',
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  value: prefs['promo_updates'] != false,
                  onChanged: _savingPref
                      ? null
                      : (v) => _togglePreference('promo_updates', v),
                  secondary: const GhstButtonIcon(Icons.card_giftcard_outlined),
                  title: const Text('Ưu đãi, sự kiện & Ví Xu'),
                  subtitle: const Text(
                    'Tích Xu đơn hoàn tất, hoàn Xu và phần thưởng sự kiện',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Text(
                    'Thông báo bảo mật, định danh hồ sơ và duyệt vai trò luôn được bật.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          widget.embedded ? 12 : 16,
          12,
          widget.embedded ? 12 : 16,
          28,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trung tâm thông báo',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _unreadCount > 0
                          ? '$_unreadCount thông báo chưa đọc'
                          : 'Tất cả thông báo đã được xem',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_unreadCount > 0)
                TextButton.icon(
                  onPressed: _busy ? null : _markAllRead,
                  icon: const GhstButtonIcon(Icons.done_all_rounded, size: 18),
                  label: const Text('Đọc tất cả'),
                ),
              IconButton(
                tooltip: 'Tùy chọn thông báo đẩy',
                onPressed: () =>
                    setState(() => _showSettings = !_showSettings),
                icon: GhstButtonIcon(
                  _showSettings
                      ? Icons.tune_rounded
                      : Icons.settings_outlined,
                ),
              ),
              IconButton(
                tooltip: 'Làm mới',
                onPressed: _busy ? null : () => _load(),
                icon: const GhstButtonIcon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_showSettings) _buildPreferencesCard(theme),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in _categories.entries) ...[
                  ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel(entry.value, size: 15), label: Text(entry.value), selected: _category == entry.key, onSelected: _busy
                        ? null
                        : (selected) {
                            if (!selected || _category == entry.key) return;
                            setState(() {
                              _category = entry.key;
                              _nextCursor = null;
                            });
                            unawaited(_load());
                          },),
                  const SizedBox(width: 8),
                ],
                FilterChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel('Chưa đọc', size: 15), label: const Text('Chưa đọc'), selected: _unreadOnly, onSelected: _busy
                      ? null
                      : (v) {
                          setState(() {
                            _unreadOnly = v;
                            _nextCursor = null;
                          });
                          unawaited(_load());
                        },),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (!_busy && _error == null && _items.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    GhstButtonIcon(
                      Icons.notifications_none_rounded,
                      size: 40,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _unreadOnly
                          ? 'Không còn thông báo chưa đọc trong mục này.'
                          : 'Chưa có thông báo phát sinh.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          for (final item in _items)
            Builder(
              builder: (context) {
                final unread = item['read_at'] == null;
                final category = '${item['category'] ?? 'shipping'}';
                final kind = '${item['kind'] ?? ''}';
                final accent = _accentFor(category, theme);
                final createdAt = cloudDate(item['created_at']);
                final catLabel = _categories[category] ?? 'Hệ thống';
                return Card(
                  elevation: unread ? 1.5 : 0.4,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: unread
                          ? accent.withValues(alpha: 0.55)
                          : theme.dividerColor.withValues(alpha: 0.45),
                      width: unread ? 1.3 : 0.9,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _tapItem(item),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: GhstButtonIcon(
                              _iconFor(category, kind),
                              color: accent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item['title'] ?? 'Thông báo'}',
                                        style: TextStyle(
                                          fontWeight: unread
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    if (unread)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(left: 8),
                                        decoration: BoxDecoration(
                                          color: accent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                if ('${item['body'] ?? ''}'.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${item['body']}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  createdAt.isNotEmpty
                                      ? '$catLabel · $createdAt'
                                      : catLabel,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 11.5,
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
              },
            ),
          if (_nextCursor != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: _loadingMore ? null : () => _load(append: true),
                icon: GhstButtonIcon.forLabel(_loadingMore ? 'Đang tải...' : 'Tải thêm thông báo', size: 16),

                label: Text(
                  _loadingMore ? 'Đang tải...' : 'Tải thêm thông báo',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
