import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/motion_3d_effects.dart';

class GhstAiChatController extends ChangeNotifier {
  GhstAiChatController({required this.session})
    : _lease = CloudSessionLease(session: session) {
    _lease.addListener(_onLeaseChanged);
  }

  static const suggestions = [
    'Đơn hàng gần nhất của tôi đang ở trạng thái nào?',
    'So sánh 5 gói giao hàng của GHST',
    'Cách tính phí quy đổi và bảo hiểm hàng hóa?',
    'Hướng dẫn dùng Voucher, đổi Xu và trả hàng',
  ];

  final CloudAccountSession session;
  final CloudSessionLease _lease;
  final List<({String role, String content})> _messages = [];

  String? _error;
  String? _retryPrompt;
  bool _busy = false;
  bool _disposed = false;
  int _generation = 0;

  List<({String role, String content})> get messages =>
      List.unmodifiable(_messages);
  String? get error => _error;
  String? get retryPrompt => _retryPrompt;
  bool get busy => _busy;
  bool get valid => !_disposed && _lease.valid;

  void _onLeaseChanged() {
    if (_disposed || _lease.valid) return;
    _generation++;
    _messages.clear();
    _error = null;
    _retryPrompt = null;
    _busy = false;
    notifyListeners();
  }

  void reset() {
    if (_disposed || _busy) return;
    _generation++;
    _messages.clear();
    _error = null;
    _retryPrompt = null;
    notifyListeners();
  }

  Future<void> send(String rawText) async {
    if (!valid || _busy) return;
    final text = rawText.trim();
    if (text.isEmpty) return;

    final generation = ++_generation;
    final nextHistory = <({String role, String content})>[
      ..._messages,
      (role: 'user', content: text),
    ];
    final bounded = nextHistory.length > 16
        ? nextHistory.sublist(nextHistory.length - 16)
        : nextHistory;

    _busy = true;
    _error = null;
    _retryPrompt = null;
    _messages
      ..clear()
      ..addAll(bounded);
    notifyListeners();

    try {
      final response = await session.service.aiChat([
        for (final turn in bounded)
          {'role': turn.role, 'content': turn.content},
      ]);
      if (!valid || generation != _generation) return;
      final reply = response['reply'];
      if (reply is! String || reply.trim().isEmpty) {
        throw const PublicApiException(
          'Trợ lý AI chưa trả về nội dung phản hồi.',
        );
      }
      _busy = false;
      final updated = <({String role, String content})>[
        ..._messages,
        (role: 'assistant', content: reply.trim()),
      ];
      if (updated.length > 16) {
        updated.removeRange(0, updated.length - 16);
      }
      _messages
        ..clear()
        ..addAll(updated);
      notifyListeners();
    } catch (err) {
      if (!valid ||
          generation != _generation ||
          _lease.handleAccessFailure(err)) {
        return;
      }
      _busy = false;
      if (_messages.isNotEmpty && _messages.last.role == 'user') {
        _messages.removeLast();
      }
      _error = err is PublicApiException
          ? err.message
          : 'Không thể kết nối Trợ lý AI trên máy chủ.';
      _retryPrompt = text;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _lease.removeListener(_onLeaseChanged);
    _lease.dispose();
    super.dispose();
  }
}

class GhstAiChatScreen extends StatefulWidget {
  const GhstAiChatScreen({super.key, required this.session, this.controller});

  final CloudAccountSession session;
  final GhstAiChatController? controller;

  @override
  State<GhstAiChatScreen> createState() => _GhstAiChatScreenState();
}

class _GhstAiChatScreenState extends State<GhstAiChatScreen> {
  GhstAiChatController? _ownedController;
  GhstAiChatController get _controller =>
      widget.controller ??
      (_ownedController ??= GhstAiChatController(session: widget.session));

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBanner(),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: GhstAiChatBody(
                    controller: _controller,
                    inputKey: const ValueKey('ghst-ai-input'),
                    sendKey: const ValueKey('ghst-ai-send'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.line),
      boxShadow: AppColors.cardShadow,
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.primaryBorder),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.primary,
            size: 19,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TRỢ LÝ AI GHST EXPRESS',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Tra cứu đơn hàng & giải đáp dịch vụ',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (_controller.messages.isNotEmpty || _controller.error != null)
          IconButton(
            tooltip: 'Làm mới hội thoại',
            onPressed: _controller.busy ? null : _controller.reset,
            icon: const Icon(
              Icons.refresh_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
      ],
    ),
  );
}

class GhstAiFloatingBubble extends StatefulWidget {
  const GhstAiFloatingBubble({
    super.key,
    required this.controller,
    this.onExpandFullScreen,
  });

  final GhstAiChatController controller;
  final VoidCallback? onExpandFullScreen;

  @override
  State<GhstAiFloatingBubble> createState() => _GhstAiFloatingBubbleState();
}

class _GhstAiFloatingBubbleState extends State<GhstAiFloatingBubble> {
  bool _open = false;
  Offset? _dragOffset;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant GhstAiFloatingBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (!widget.controller.valid && _open) {
      setState(() => _open = false);
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 860;
      final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
      final baseBottom = (wide ? 20.0 : 76.0) + bottomInset;
      const bubbleWidth = 52.0;
      const bubbleHeight = 52.0;

      final defaultLeft = (constraints.maxWidth - bubbleWidth - 16).clamp(
        8.0,
        constraints.maxWidth,
      );
      final defaultTop = (constraints.maxHeight - bubbleHeight - baseBottom)
          .clamp(8.0, constraints.maxHeight);
      final maxLeft = (constraints.maxWidth - bubbleWidth - 8).clamp(
        8.0,
        constraints.maxWidth,
      );
      final maxTop =
          (constraints.maxHeight - bubbleHeight - (wide ? 12.0 : 70.0)).clamp(
            8.0,
            constraints.maxHeight,
          );

      final pos = _dragOffset == null
          ? Offset(defaultLeft, defaultTop)
          : Offset(
              _dragOffset!.dx.clamp(8.0, maxLeft),
              _dragOffset!.dy.clamp(8.0, maxTop),
            );

      if (!_open) {
        final hasMessages = widget.controller.messages.isNotEmpty;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: pos.dx,
              top: pos.dy,
              child: GestureDetector(
                excludeFromSemantics: true,
                onPanUpdate: (details) => setState(() {
                  final base = _dragOffset ?? pos;
                  _dragOffset = Offset(
                    (base.dx + details.delta.dx).clamp(8.0, maxLeft),
                    (base.dy + details.delta.dy).clamp(8.0, maxTop),
                  );
                }),
                child: Material(
                  color: Colors.transparent,
                  child: Tooltip(
                    message: 'Mở bong bóng Trợ lý AI',
                    excludeFromSemantics: true,
                    child: Semantics(
                      button: true,
                      label: 'Mở bong bóng Trợ lý AI',
                      child: Motion3dInteractiveSurface(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(16),
                        ),
                        maxTilt: 0.055,
                        pressScale: 0.955,
                        hoverLift: -1.8,
                        child: InkWell(
                          key: const ValueKey('ghst-ai-floating-bubble'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => setState(() => _open = true),
                          child: Motion3dFloatingLayer(
                            floatAmplitude: 2.2,
                            tiltAmplitude: 0.020,
                            child: Container(
                              width: bubbleWidth,
                              height: bubbleHeight,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            boxShadow: AppColors.elevatedShadow,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                color: Colors.white,
                                size: 23,
                              ),
                              if (hasMessages)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: AppColors.acid,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.primary,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }

      final availableHeight = (constraints.maxHeight - baseBottom - 16).clamp(
        220.0,
        520.0,
      );
      final panelWidth = (constraints.maxWidth - 24).clamp(260.0, 380.0);
      final panelHeight = (constraints.maxHeight * 0.58).clamp(
        220.0,
        availableHeight,
      );

      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: 12,
            bottom: baseBottom,
            width: panelWidth,
            height: panelHeight,
            child: Motion3dSectionTransition(
              transitionKey: _open,
              originAlignment: Alignment.bottomRight,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  key: const ValueKey('ghst-ai-floating-panel'),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line),
                  boxShadow: AppColors.elevatedShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.techBg,
                        border: Border(
                          bottom: BorderSide(color: AppColors.techLine),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                          const SizedBox(width: 9),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CHAT AI GHST',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Trợ lý trực tuyến',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.techMuted,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.controller.messages.isNotEmpty ||
                              widget.controller.error != null)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Làm mới hội thoại',
                              onPressed: widget.controller.busy
                                  ? null
                                  : widget.controller.reset,
                              icon: const Icon(
                                Icons.refresh_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          if (widget.onExpandFullScreen != null)
                            IconButton(
                              key: const ValueKey('ghst-ai-bubble-expand'),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Mở toàn màn hình',
                              onPressed: () {
                                setState(() => _open = false);
                                widget.onExpandFullScreen!();
                              },
                              icon: const Icon(
                                Icons.open_in_full_rounded,
                                color: Colors.white,
                                size: 17,
                              ),
                            ),
                          IconButton(
                            key: const ValueKey('ghst-ai-bubble-close'),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Thu gọn bong bóng chat',
                            onPressed: () => setState(() => _open = false),
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GhstAiChatBody(
                        controller: widget.controller,
                        compact: true,
                        inputKey: const ValueKey('ghst-ai-bubble-input'),
                        sendKey: const ValueKey('ghst-ai-bubble-send'),
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class GhstAiChatBody extends StatefulWidget {
  const GhstAiChatBody({
    super.key,
    required this.controller,
    required this.inputKey,
    required this.sendKey,
    this.compact = false,
  });

  final GhstAiChatController controller;
  final Key inputKey;
  final Key sendKey;
  final bool compact;

  @override
  State<GhstAiChatBody> createState() => _GhstAiChatBodyState();
}

class _GhstAiChatBodyState extends State<GhstAiChatBody> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.controller.messages.length;
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant GhstAiChatBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      _lastCount = widget.controller.messages.length;
      widget.controller.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (!mounted) return;
    if (!widget.controller.valid) _input.clear();
    final count = widget.controller.messages.length;
    if (count != _lastCount) {
      _lastCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.controller.busy) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    unawaited(widget.controller.send(text));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.error != null) _buildErrorStrip(c),
        Expanded(
          child: c.messages.isEmpty && !c.busy
              ? _buildEmptyState(c)
              : _buildMessageList(c),
        ),
        const Divider(color: AppColors.line, height: 1),
        _buildComposer(c),
      ],
    );
  }

  Widget _buildErrorStrip(GhstAiChatController c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      border: Border(
        bottom: BorderSide(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: AppColors.danger,
          size: 17,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            c.error!,
            style: const TextStyle(
              color: AppColors.danger,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (c.retryPrompt != null && !c.busy)
          TextButton(
            onPressed: () => unawaited(c.send(c.retryPrompt!)),
            child: const Text('Gửi lại'),
          ),
      ],
    ),
  );

  Widget _buildEmptyState(GhstAiChatController c) => SingleChildScrollView(
    padding: EdgeInsets.all(widget.compact ? 12 : 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Xin chào! Tôi có thể hỗ trợ bạn kiểm tra trạng thái đơn hàng, tính cước vận chuyển 5 chế độ, chính sách bảo hiểm, Voucher & Xu hoặc hậu mãi.',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: widget.compact ? 12.5 : 13.5,
            fontWeight: FontWeight.w500,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Gợi ý câu hỏi nhanh',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in GhstAiChatController.suggestions)
              OutlinedButton(
                onPressed: c.busy ? null : () => unawaited(c.send(suggestion)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.surfaceSubtle,
                  foregroundColor: AppColors.ink,
                  side: const BorderSide(color: AppColors.line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? 10 : 12,
                    vertical: widget.compact ? 7 : 9,
                  ),
                ),
                child: Text(
                  suggestion,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: widget.compact ? 11.5 : 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _buildMessageList(GhstAiChatController c) => SelectionArea(
    child: ListView.separated(
      controller: _scroll,
      padding: EdgeInsets.all(widget.compact ? 10 : 14),
      itemCount: c.messages.length + (c.busy ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == c.messages.length) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Trợ lý AI đang phản hồi...',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final turn = c.messages[index];
        final isUser = turn.role == 'user';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.compact ? 290 : 680),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(14),
                border: isUser ? null : Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUser ? 'BẠN' : 'TRỢ LÝ AI',
                    style: TextStyle(
                      color: isUser
                          ? Colors.white.withValues(alpha: 0.85)
                          : AppColors.primary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    turn.content,
                    style: TextStyle(
                      color: isUser ? Colors.white : AppColors.ink,
                      fontSize: widget.compact ? 12.5 : 13.5,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _buildComposer(GhstAiChatController c) => Padding(
    padding: EdgeInsets.all(widget.compact ? 8 : 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            key: widget.inputKey,
            controller: _input,
            enabled: !c.busy,
            minLines: 1,
            maxLines: widget.compact ? 3 : 4,
            maxLength: 2000,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Nhập câu hỏi cho Trợ lý AI',
              counterText: '',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: widget.compact ? 9 : 11,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: widget.sendKey,
          onPressed: c.busy ? null : _submit,
          icon: const Icon(Icons.send_rounded, size: 16),
          label: const Text('Gửi'),
        ),
      ],
    ),
  );
}
