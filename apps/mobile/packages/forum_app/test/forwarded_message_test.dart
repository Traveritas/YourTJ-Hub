import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/l10n/app_localizations.dart';
import 'package:forum_app/src/format.dart';
import 'package:forum_app/src/messages/forwarded_message.dart';
import 'package:forum_app/src/providers.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_visible_read_test.dart' show pumpChat;
import 'fixtures/page_fixtures.dart' show messagesPayloadJson, parsePayload;
import 'pages_behavior_test.dart' show CountingPageRepository, MemTokenStorage;

class _ForwardPreviewRepository extends CountingPageRepository {
  _ForwardPreviewRepository()
    : super(GfApiClient(dio: Dio(), tokenStorage: MemTokenStorage()));
  @override
  Future<PagePayload> fetch(String path, {Object? cancelToken}) async {
    if (path != '/messages') return super.fetch(path, cancelToken: cancelToken);
    final payload = messagesPayloadJson();
    final conversations = (payload['props'] as Map)['conversations'] as List;
    (conversations.first as Map)['lastMsg'] =
        '[Chat history]\nBob: [:sticker:smile:]';
    return parsePayload(payload);
  }
}

void main() {
  testWidgets(
    'conversation preview includes the forwarded content on one line',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await pumpChat(
        tester,
        targetUserId: null,
        overrides: [
          pageRepositoryProvider.overrideWithValue(_ForwardPreviewRepository()),
        ],
      );
      final row = tester.widget<GfConversationRow>(
        find.byType(GfConversationRow).first,
      );
      expect(row.lastMessage, '[Chat history] Bob: [smile]');
    },
  );

  testWidgets(
    'snapshot detail shows a single full timestamp and hides on account change',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const time = '2026-09-28T01:00:00Z';
      const bundle = ChatForwardBundle(
        version: 1,
        messages: [
          ChatForwardEntry(
            senderName: 'Alice',
            content: 'copied private body',
            createdAt: time,
            msgType: 1,
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: gfThemeData(Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ForwardedMessagesPage(bundle: bundle, ownerEpoch: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(formatDateTime(time)), findsOneWidget);
      expect(find.text('copied private body'), findsOneWidget);
      expect(find.byType(GfAvatar), findsOneWidget);
      expect(find.byType(GfMessageBubble), findsOneWidget);
      expect(find.byType(GfChatInput), findsNothing);
      expect(
        tester.getTopLeft(find.byType(GfAvatar)).dx,
        lessThan(tester.getTopLeft(find.text('copied private body')).dx),
      );
      container.read(offlineCacheEpochProvider.notifier).invalidate();
      await tester.pump();
      expect(find.text('copied private body'), findsNothing);
      expect(find.text('Alice'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
