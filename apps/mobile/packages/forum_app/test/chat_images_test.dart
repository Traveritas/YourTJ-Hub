import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/src/images/image_upload.dart';
import 'package:forum_app/src/messages/chat_image.dart';
import 'package:forum_app/src/providers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

import 'chat_message_actions_test.dart' show RecordingSendsChatRepository;
import 'chat_visible_read_test.dart' show pumpChat;
import 'fixtures/page_fixtures.dart' show messagesPayloadJson, parsePayload;
import 'pages_behavior_test.dart' show MemTokenStorage, makeChatMessage;

final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
);

class _ImagePreviewPageRepository extends PageRepository {
  _ImagePreviewPageRepository(this.preview)
    : super(GfApiClient(dio: Dio(), tokenStorage: MemTokenStorage()));

  final String preview;

  @override
  Future<PagePayload> fetch(String path, {Object? cancelToken}) async {
    final json = messagesPayloadJson();
    final props = json['props'] as Map<String, dynamic>;
    final conversations = props['conversations'] as List;
    (conversations.first as Map<String, dynamic>)['lastMsg'] = preview;
    return parsePayload(json);
  }
}

class _Photos extends ImagePicker {
  Completer<XFile?>? gate;
  XFile? file = XFile.fromData(_png, name: 'photo.png', path: 'photo.png');
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    expect(source, ImageSource.gallery);
    expect(requestFullMetadata, isFalse);
    return gate == null ? file : gate!.future;
  }
}

class _Files extends FileRepository {
  _Files() : super(GfApiClient(dio: Dio(), tokenStorage: MemTokenStorage()));
  int calls = 0;
  bool fail = false;
  Completer<String>? gate;
  @override
  Future<String> uploadImage({
    required List<int> bytes,
    required String filename,
  }) async {
    calls++;
    expect(bytes, _png);
    expect(filename, 'photo.png');
    if (fail) throw StateError('upload unavailable');
    return gate == null ? '/file/img/photo.png' : gate!.future;
  }
}

void main() {
  late _Photos photos;
  late _Files files;
  late RecordingSendsChatRepository chat;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    photos = _Photos();
    files = _Files();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<ChatMessagePayload>? messages,
  }) async {
    final result = await pumpChat(
      tester,
      repository: (client) => chat = RecordingSendsChatRepository(
        client,
        messages: messages ?? [makeChatMessage(1)],
      ),
      overrides: [
        imagePickerProvider.overrideWithValue(photos),
        fileRepositoryProvider.overrideWithValue(files),
      ],
    );
    return result.container;
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('chat-attach')));
    await tester.pumpAndSettle();
    expect(find.text('Add sticker'), findsOneWidget);
    await tester.tap(find.text('Add image'));
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  for (final (content, preview) in [
    ('/file/2026/09/30/photo.png', '[Image]'),
    ('https://cdn.example.com/PHOTO.JPEG?token=abc#image', '[Image]'),
    ('https://cdn.example.com/animation.webp', '[Image]'),
    ('https://example.com/topic/123', 'https://example.com/topic/123'),
    (
      'https://example.com/?file=photo.png',
      'https://example.com/?file=photo.png',
    ),
    ('photo: /file/photo.png', 'photo: /file/photo.png'),
  ]) {
    testWidgets('conversation image preview handles $content', (tester) async {
      await pumpChat(
        tester,
        targetUserId: null,
        overrides: [
          pageRepositoryProvider.overrideWithValue(
            _ImagePreviewPageRepository(content),
          ),
        ],
      );
      final row = tester
          .widgetList<GfConversationRow>(find.byType(GfConversationRow))
          .firstWhere((row) => row.name == 'bob');
      expect(row.lastMessage, preview);
      expect(find.text(preview), findsOneWidget);
      await dispose(tester);
    });
  }

  testWidgets(
    'image selection previews before upload and cancel preserves draft',
    (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField).last, 'unsent text');
      await choose(tester);
      expect(find.byType(ChatImagePreview), findsOneWidget);
      expect(files.calls, 0);
      expect(chat.sent, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(files.calls, 0);
      expect(find.text('unsent text'), findsOneWidget);
      await dispose(tester);
    },
  );

  testWidgets(
    'upload failure retains preview; failed image send retries without reupload or losing text',
    (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField).last, 'keep my draft');
      await choose(tester);
      files.fail = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatImagePreview), findsOneWidget);
      expect(chat.sent, isEmpty);
      files.fail = false;
      chat.failures = 1;
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatImagePreview), findsNothing);
      expect(files.calls, 2);
      expect(chat.sentTypes, [2]);
      expect(chat.sent.single.$2, '/file/img/photo.png');
      expect(find.byType(ChatImage), findsOneWidget);
      expect(find.text('keep my draft'), findsOneWidget);
      await tester.tap(find.text('Retry sending'));
      await tester.pumpAndSettle();
      expect(files.calls, 2);
      expect(chat.sentTypes, [2, 2]);
      expect(chat.clientKeys[1], chat.clientKeys[0]);
      expect(find.text('keep my draft'), findsOneWidget);
      await dispose(tester);
    },
  );

  testWidgets('late photo selection after account change never uploads', (
    tester,
  ) async {
    final container = await pump(tester);
    photos.gate = Completer<XFile?>();
    await choose(tester);
    container.read(offlineCacheEpochProvider.notifier).invalidate();
    photos.gate!.complete(photos.file);
    await tester.pumpAndSettle();
    expect(files.calls, 0);
    expect(chat.sent, isEmpty);
    await dispose(tester);
  });

  testWidgets('late upload after account change never sends an image', (
    tester,
  ) async {
    final container = await pump(tester);
    await choose(tester);
    files.gate = Completer<String>();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pump();
    container.read(offlineCacheEpochProvider.notifier).invalidate();
    files.gate!.complete('/file/img/photo.png');
    await tester.pumpAndSettle();
    expect(chat.sent, isEmpty);
    expect(find.byType(Image), findsNothing);
    await dispose(tester);
  });

  testWidgets('replying to an image uses a readable quote and its message ID', (
    tester,
  ) async {
    await pump(
      tester,
      messages: [
        makeChatMessage(1).copyWith(content: '/file/img/photo.png', msgType: 2),
      ],
    );
    await tester.longPress(find.byType(ChatImage));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.text('[Image]'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'nice photo');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(chat.sent.single.$2, contains('[Image]\n\nnice photo'));
    expect(chat.replyTargets, [1]);
    expect(chat.sentTypes, [1]);
    await dispose(tester);
  });

  testWidgets(
    'received images open the viewer and unsafe image content stays text',
    (tester) async {
      await pump(
        tester,
        messages: [
          makeChatMessage(
            1,
          ).copyWith(content: '/file/img/photo.png', msgType: 2),
          makeChatMessage(
            2,
          ).copyWith(content: 'javascript:alert(1)', msgType: 2),
        ],
      );
      expect(find.byType(ChatImage), findsOneWidget);
      expect(find.text('javascript:alert(1)'), findsOneWidget);
      await tester.tap(find.byType(ChatImage));
      await tester.pumpAndSettle();
      expect(find.byType(GfImageViewer), findsOneWidget);
      await dispose(tester);
    },
  );
}
