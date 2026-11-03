import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/presentation/customer/ghst_ai_chat_screen.dart';
import 'package:gps_delivery_app/presentation/customer/ghst_user_shell.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unified_user_interface_test.dart' show UnifiedUserFixture;

class AiChatFixture extends UnifiedUserFixture {
  bool unconfigured = false;
  String model = 'gpt-4o-mini';
  String reply = 'Đơn CL-AI-001 của bạn đang trên đường giao.';
  Completer<Map<String, dynamic>>? pendingChat;
  final List<List<Map<String, dynamic>>> chatPayloads = [];

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == 'ai-chat') {
      final raw = (body?['messages'] as List?) ?? const [];
      chatPayloads.add([
        for (final item in raw) Map<String, dynamic>.from(item as Map),
      ]);
      if (pendingChat != null) return pendingChat!.future;
      if (unconfigured) {
        throw const PublicApiException(
          'Trợ lý AI chưa được cấu hình hoặc đang tạm tắt trên máy chủ.',
          statusCode: 503,
        );
      }
      return {'reply': reply, 'model': model};
    }
    return super.request(path, body: body, query: query);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(AiChatFixture, CloudAccountSession)> setup(
    WidgetTester tester,
    double width,
  ) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    final api = AiChatFixture();
    final session = CloudAccountSession(service: api);
    addTearDown(() async {
      session.dispose();
      await api.changes.close();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await session.refresh();
    return (api, session);
  }

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'Customer AI chatbot sends multi-turn messages via backend inside shell at $width',
      (tester) async {
        final (api, session) = await setup(tester, width);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: MarketplaceScreen(session: session),
          ),
        );
        await tester.pumpAndSettle();

        final homeBtn = find.text('Hỏi Trợ lý AI');
        await tester.ensureVisible(homeBtn);
        await tester.tap(homeBtn);
        await tester.pumpAndSettle();

        expect(find.byType(GhstAiChatScreen), findsOneWidget);
        expect(
          find.byKey(const ValueKey('ghst-ai-floating-bubble')),
          findsNothing,
        );
        expect(find.byType(GhstUserShell), findsOneWidget);
        expect(
          Navigator.of(tester.element(find.byType(MarketplaceScreen))).canPop(),
          isFalse,
        );

        await tester.tap(
          find.text('Đơn hàng gần nhất của tôi đang ở trạng thái nào?'),
        );
        await tester.pumpAndSettle();

        expect(api.chatPayloads, hasLength(1));
        expect(api.chatPayloads.single, [
          {
            'role': 'user',
            'content': 'Đơn hàng gần nhất của tôi đang ở trạng thái nào?',
          },
        ]);
        expect(
          find.text('Đơn CL-AI-001 của bạn đang trên đường giao.'),
          findsOneWidget,
        );
        expect(find.text('gpt-4o-mini'), findsNothing);

        api.reply = 'Phí giao nhanh được tính theo khoảng cách thực tế.';
        await tester.enterText(
          find.byKey(const ValueKey('ghst-ai-input')),
          'Cước giao nhanh tính thế nào?',
        );
        await tester.tap(find.byKey(const ValueKey('ghst-ai-send')));
        await tester.pumpAndSettle();

        expect(api.chatPayloads, hasLength(2));
        expect(api.chatPayloads.last, hasLength(3));
        expect(api.chatPayloads.last[1]['role'], 'assistant');
        expect(api.chatPayloads.last[2]['content'], 'Cước giao nhanh tính thế nào?');
        expect(
          find.text('Phí giao nhanh được tính theo khoảng cách thực tế.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'Unconfigured backend AI shows honest 503 error without mock reply and supports retry',
    (tester) async {
      final (api, session) = await setup(tester, 360);
      api.unconfigured = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MarketplaceScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ghst-mobile-header-ai')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('ghst-ai-input')),
        'Kiểm tra đơn hàng',
      );
      await tester.tap(find.byKey(const ValueKey('ghst-ai-send')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Trợ lý AI chưa được cấu hình hoặc đang tạm tắt trên máy chủ.',
        ),
        findsOneWidget,
      );
      expect(find.text('TRỢ LÝ AI'), findsNothing);

      api.unconfigured = false;
      api.reply = 'Đã kết nối lại thành công với backend AI.';
      await tester.tap(find.text('Gửi lại'));
      await tester.pumpAndSettle();

      expect(
        find.text('Đã kết nối lại thành công với backend AI.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Late AI reply is discarded and history is cleared on session revocation',
    (tester) async {
      final (api, session) = await setup(tester, 1440);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MarketplaceScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ghst-header-ai')));
      await tester.pumpAndSettle();

      final delayed = Completer<Map<String, dynamic>>();
      api.pendingChat = delayed;
      await tester.enterText(
        find.byKey(const ValueKey('ghst-ai-input')),
        'Thông tin riêng tư của tài khoản cũ',
      );
      await tester.tap(find.byKey(const ValueKey('ghst-ai-send')));
      await tester.pump();

      session.invalidateVerification(
        error: const PublicApiException('Revoked', statusCode: 403),
      );
      await tester.pumpAndSettle();

      delayed.complete({
        'reply': 'PRIVATE OLD ACCOUNT REPLY',
        'model': 'gpt-4o-mini',
      });
      await tester.pumpAndSettle();

      expect(find.textContaining('PRIVATE OLD ACCOUNT REPLY'), findsNothing);
      expect(
        find.textContaining('Thông tin riêng tư của tài khoản cũ'),
        findsNothing,
      );
      expect(find.byType(GhstAiChatScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'Floating AI chat bubble opens overlay, drags, persists across tabs, and expands to full screen at $width',
      (tester) async {
        final (api, session) = await setup(tester, width);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: MarketplaceScreen(session: session),
          ),
        );
        await tester.pumpAndSettle();

        final bubble = find.byKey(const ValueKey('ghst-ai-floating-bubble'));
        expect(bubble, findsOneWidget);

        final beforePos = tester.getTopLeft(bubble);
        await tester.drag(bubble, const Offset(-30, -40));
        await tester.pumpAndSettle();
        final afterPos = tester.getTopLeft(bubble);
        expect(afterPos.dx, lessThan(beforePos.dx));
        expect(afterPos.dy, lessThan(beforePos.dy));

        await tester.tap(bubble);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('ghst-ai-floating-panel')),
          findsOneWidget,
        );
        expect(
          Navigator.of(tester.element(find.byType(MarketplaceScreen))).canPop(),
          isFalse,
        );

        api.reply = 'Phản hồi trực tiếp ngay trong bong bóng nổi!';
        await tester.enterText(
          find.byKey(const ValueKey('ghst-ai-bubble-input')),
          'Hỏi nhanh từ bong bóng chat',
        );
        await tester.tap(find.byKey(const ValueKey('ghst-ai-bubble-send')));
        await tester.pumpAndSettle();

        expect(
          find.text('Phản hồi trực tiếp ngay trong bong bóng nổi!'),
          findsOneWidget,
        );
        expect(find.text('gpt-4o-mini'), findsNothing);
        expect(find.text('Trợ lý trực tuyến'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('ghst-ai-bubble-close')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('ghst-ai-floating-panel')),
          findsNothing,
        );
        expect(bubble, findsOneWidget);

        await tester.tap(bubble);
        await tester.pumpAndSettle();
        expect(
          find.text('Phản hồi trực tiếp ngay trong bong bóng nổi!'),
          findsOneWidget,
        );
        expect(find.text('gpt-4o-mini'), findsNothing);
        expect(find.text('Trợ lý trực tuyến'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('ghst-ai-bubble-expand')));
        await tester.pumpAndSettle();
        expect(find.byType(GhstAiChatScreen), findsOneWidget);
        expect(bubble, findsNothing);
        expect(
          find.text('Phản hồi trực tiếp ngay trong bong bóng nổi!'),
          findsOneWidget,
        );
        expect(find.text('gpt-4o-mini'), findsNothing);
        expect(find.text('TRỢ LÝ AI GHST EXPRESS'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
