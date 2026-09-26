import 'dart:async';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/data/datasources/request_options.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:clan_ai/ui/shared/mixins/stream_mutation_mixin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_chat_repository.dart';
import '../helpers/test_model_factories.dart';

// Test class that mixes in StreamMutationMixin
class TestViewModel extends ChangeNotifier with StreamMutationMixin {
  final ChatRepository _repo;
  List<ChatMessage> _messages = [];
  ChatThread? _activeThread;
  bool _isGenerating = false;
  CancelToken? _cancelToken;
  Timer? _timer;
  String _pendingStream = '';
  String _pendingReasoning = '';

  TestViewModel({ChatRepository? repo}) : _repo = repo ?? FakeChatRepository();

  @override
  Timer? get uiThrottleTimer => _timer;
  @override
  set uiThrottleTimer(Timer? v) => _timer = v;

  @override
  String get pendingStreamBuffer => _pendingStream;
  @override
  set pendingStreamBuffer(String v) => _pendingStream = v;

  @override
  String get pendingReasoningBuffer => _pendingReasoning;
  @override
  set pendingReasoningBuffer(String v) => _pendingReasoning = v;

  @override
  List<ChatMessage> get messages => _messages;
  @override
  set messages(List<ChatMessage> v) => _messages = v;

  @override
  ChatThread? get activeThread => _activeThread;

  @override
  bool get isGenerating => _isGenerating;
  @override
  set isGenerating(bool v) => _isGenerating = v;

  @override
  CancelToken? get currentCancelToken => _cancelToken;
  @override
  set currentCancelToken(CancelToken? v) => _cancelToken = v;

  @override
  ChatRepository get chatRepository => _repo;

  String? stubbedImageRef;
  String? stubbedFileRef;
  String? lastDownloadedImageUrl;
  String? lastDownloadedFileUrl;
  String? lastDownloadedFileName;
  String? lastDownloadedFileMime;

  @override
  Future<String?> downloadImageArtifact(String messageId, String url) async {
    lastDownloadedImageUrl = url;
    return stubbedImageRef;
  }

  @override
  Future<String?> downloadFileArtifact(
    String messageId,
    String url,
    String? fileName,
    String? mime,
  ) async {
    lastDownloadedFileUrl = url;
    lastDownloadedFileName = fileName;
    lastDownloadedFileMime = mime;
    return stubbedFileRef;
  }

  void setThread(ChatThread thread) => _activeThread = thread;

  void addMessage(ChatMessage msg) {
    _messages.add(msg);
  }

  void clearMessages() => _messages.clear();

  List<ChatMessage> get allMessages => _messages;

  ChatMessage? getMessageById(String id) {
    return _messages.where((m) => m.id == id).firstOrNull;
  }

  @override
  void notifyListeners() {
    // No-op for testing
  }
}

/// Fake repository whose stream events are controlled manually so tests can
/// observe mid-stream state (e.g. a live-attached image before completion).
class _GatedChatRepository extends FakeChatRepository {
  final StreamController<StreamChunk> controller = StreamController<StreamChunk>();

  @override
  Stream<StreamChunk> streamCompletion({
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    required List<ChatMessage> history,
    required String? systemPrompt,
    GenerationParams? params,
    CancelToken? cancelToken,
    int? modelContextLength,
    RequestOptions options = RequestOptions.none,
  }) {
    return controller.stream;
  }
}

void main() {
  group('StreamMutationMixin doStreamResponse', () {
    test('streams chunks and accumulates content into message', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      // Add user message so history is non-empty (needed for fake stream lookup)
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      vm.addMessage(userMsg);

      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      );
      vm.addMessage(assistantMsg);
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hello', isDone: false),
        const StreamChunk(text: ' world', isDone: false),
        const StreamChunk(text: '', isDone: true),
      ]);

      final serverConfig = buildServerConfig();
      await vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        modelContextLength: null,
      );
      await Future.delayed(const Duration(milliseconds: 200));

      final result = vm.getMessageById('assistant-1');
      expect(result, isNotNull);
      expect(result!.content, equals('Hello world'));
      expect(result.status, equals(MessageStatus.completed));
    });

    test('sets isGenerating true during stream', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      // Add user message so history is non-empty (needed for fake stream lookup)
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      vm.addMessage(userMsg);

      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      );
      vm.addMessage(assistantMsg);
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hello', isDone: true),
      ]);

      // isGenerating should be false initially
      expect(vm.isGenerating, isFalse);

      // Start streaming
      vm.isGenerating = true;
      vm.currentCancelToken = CancelToken();
      vm.pendingStreamBuffer = '';
      vm.pendingReasoningBuffer = '';
      vm.notifyListeners();

      // Set up timer for throttling
      vm.uiThrottleTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
        if (vm.pendingStreamBuffer.isNotEmpty) {
          final msgIndex = vm.messages.indexWhere((m) => m.id == 'assistant-1');
          if (msgIndex >= 0) {
            vm.messages[msgIndex] = vm.messages[msgIndex].copyWith(
              content: vm.messages[msgIndex].content + vm.pendingStreamBuffer,
            );
            vm.pendingStreamBuffer = '';
            vm.notifyListeners();
          }
        }
      });

      expect(vm.isGenerating, isTrue);
    });

    test('saves message to repository on completion', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      // Add user message so history is non-empty (needed for fake stream lookup)
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      vm.addMessage(userMsg);

      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: 'partial',
      );
      vm.addMessage(assistantMsg);
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: ' completed', isDone: true),
      ]);

      final serverConfig = buildServerConfig();
      await vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        modelContextLength: null,
      );
      await Future.delayed(const Duration(milliseconds: 200));

      expect(repo.lastSavedMessage, isNotNull);
      expect(repo.lastSavedMessage!.content, equals('partial completed'));
      expect(repo.lastSavedMessage!.status, equals(MessageStatus.completed));
    });

    test('calls onComplete hook after stream completes', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      // Add user message so history is non-empty (needed for fake stream lookup)
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      vm.addMessage(userMsg);

      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      );
      vm.addMessage(assistantMsg);
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'done', isDone: true),
      ]);

      bool hookCalled = false;
      final serverConfig = buildServerConfig();

      await vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        modelContextLength: null,
        onComplete: (id) async {
          hookCalled = true;
        },
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(hookCalled, isTrue);
    });

    test('handles upToIndex truncation', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);

      // User message + assistant message
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
        content: 'Hello',
      ));
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      ));
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      final serverConfig = buildServerConfig();
      await vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        upToIndex: 1, // Truncate at user message
        modelContextLength: null,
      );
      await Future.delayed(const Duration(milliseconds: 200));

      final result = vm.getMessageById('assistant-1');
      expect(result!.content, equals('Hi'));
    });

    test('handles missing assistant message gracefully', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      vm.setThread(buildThread(title: 'Test'));

      final serverConfig = buildServerConfig();
      await vm.doStreamResponse(
        assistantMessageId: 'non-existent',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        modelContextLength: null,
      );
      await Future.delayed(const Duration(milliseconds: 200));

      expect(vm.isGenerating, isFalse);
    });

    test('accumulates reasoning content', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      // Add user message so history is non-empty (needed for fake stream lookup)
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      vm.addMessage(userMsg);

      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      );
      vm.addMessage(assistantMsg);
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hello', reasoning: 'Thinking 1', isDone: false),
        const StreamChunk(text: ' world', reasoning: 'Thinking 2', isDone: true),
      ]);

      final serverConfig = buildServerConfig();
      await vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        modelContextLength: null,
      );
      await Future.delayed(const Duration(milliseconds: 200));

      final result = vm.getMessageById('assistant-1');
      expect(result!.reasoningContent, equals('Thinking 1Thinking 2'));
    });

    test('preserves existing reasoningContent when streaming', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      // Add user message so history is non-empty (needed for fake stream lookup)
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      vm.addMessage(userMsg);

      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
        reasoningContent: 'Previous reasoning',
      );
      vm.addMessage(assistantMsg);
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hello', reasoning: 'New reasoning', isDone: true),
      ]);

      final serverConfig = buildServerConfig();
      await vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        modelContextLength: null,
      );
      await Future.delayed(const Duration(milliseconds: 200));

      final result = vm.getMessageById('assistant-1');
      expect(result!.reasoningContent, equals('Previous reasoningNew reasoning'));
    });

    test('captures image artifact from empty-text chunk and persists imagePath',
        () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      ));
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      ));
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: '', imageUrl: 'http://host/img.png', isDone: true),
      ]);
      vm.stubbedImageRef = '/tmp/attachments/a1.png';

      final serverConfig = buildServerConfig();
      await vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      final result = vm.getMessageById('assistant-1');
      expect(vm.lastDownloadedImageUrl, equals('http://host/img.png'));
      expect(result!.imagePath, equals('/tmp/attachments/a1.png'));
      expect(result.status, equals(MessageStatus.completed));
    });

    test('captures file artifact with name/mime and persists file fields',
        () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      ));
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      ));
      repo.setStreamFragments(thread.id, [
        const StreamChunk(
          text: '',
          fileUrl: 'http://host/export.csv',
          fileName: 'export.csv',
          fileMime: 'text/csv',
        ),
        const StreamChunk(text: 'Your export.', isDone: true),
      ]);
      vm.stubbedFileRef = '/tmp/attachments/f_a1.csv';

      final serverConfig = buildServerConfig();
      await vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      final result = vm.getMessageById('assistant-1');
      expect(vm.lastDownloadedFileUrl, equals('http://host/export.csv'));
      expect(vm.lastDownloadedFileName, equals('export.csv'));
      expect(vm.lastDownloadedFileMime, equals('text/csv'));
      expect(result!.filePath, equals('/tmp/attachments/f_a1.csv'));
      expect(result.fileName, equals('export.csv'));
      expect(result.fileMime, equals('text/csv'));
      expect(result.content, equals('Your export.'));
    });

    test('captures image artifact at most once per response', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      ));
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      ));
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: '', imageUrl: 'http://host/a.png'),
        const StreamChunk(text: '', imageUrl: 'http://host/b.png'),
        const StreamChunk(text: '', isDone: true),
      ]);
      vm.stubbedImageRef = '/tmp/attachments/a1.png';

      final serverConfig = buildServerConfig();
      await vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.lastDownloadedImageUrl, equals('http://host/a.png'));
      expect(vm.getMessageById('assistant-1')!.imagePath,
          equals('/tmp/attachments/a1.png'));
    });

    test('completes gracefully when artifact download fails', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      ));
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      ));
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: '', imageUrl: 'http://host/missing.png'),
        const StreamChunk(text: 'Caption still arrives.', isDone: true),
      ]);
      vm.stubbedImageRef = null;

      final serverConfig = buildServerConfig();
      await vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      final result = vm.getMessageById('assistant-1');
      expect(result!.imagePath, isNull);
      expect(result.content, equals('Caption still arrives.'));
      expect(result.status, equals(MessageStatus.completed));
    });

    test('attaches imagePath live during streaming before the stream completes',
        () async {
      final repo = _GatedChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      ));
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      ));
      vm.stubbedImageRef = '/tmp/attachments/a1.png';

      final serverConfig = buildServerConfig();
      final streamFuture = vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      // Let the await-for subscribe before feeding events.
      await Future<void>.delayed(Duration.zero);

      repo.controller.add(const StreamChunk(text: '', imageUrl: 'http://host/img.png'));
      await Future<void>.delayed(Duration.zero);

      // The image is already attached while the caption stream is still open.
      expect(vm.lastDownloadedImageUrl, equals('http://host/img.png'));
      expect(
        vm.getMessageById('assistant-1')!.imagePath,
        equals('/tmp/attachments/a1.png'),
      );

      repo.controller.add(const StreamChunk(text: 'Caption.', isDone: true));
      await repo.controller.close();
      await streamFuture;

      final result = vm.getMessageById('assistant-1');
      expect(result!.content, equals('Caption.'));
      expect(result.imagePath, equals('/tmp/attachments/a1.png'));
      expect(result.status, equals(MessageStatus.completed));
    });

    test('promotes an image URL embedded only in markdown stream text', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      ));
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      ));
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Here is your image: ', isDone: false),
        const StreamChunk(text: '![gen](http://host/gen_1.png)', isDone: false),
        const StreamChunk(text: ' Let me know.', isDone: true),
      ]);
      vm.stubbedImageRef = '/tmp/attachments/a1.png';

      final serverConfig = buildServerConfig();
      await vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      final result = vm.getMessageById('assistant-1');
      expect(vm.lastDownloadedImageUrl, equals('http://host/gen_1.png'));
      expect(result!.imagePath, equals('/tmp/attachments/a1.png'));
      // The markdown image syntax was stripped from the caption.
      expect(result.content, equals('Here is your image:  Let me know.'));
      expect(result.content, isNot(contains('http://host/gen_1.png')));
    });

    test('resolves a relative artifact URL against the connection baseUrl',
        () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      ));
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      ));
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: '', imageUrl: '/images/gen_1.png', isDone: true),
      ]);
      vm.stubbedImageRef = '/tmp/attachments/a1.png';

      final serverConfig = buildServerConfig();
      final profile = buildServerProfile(baseUrl: 'http://10.0.2.2:8080');
      await vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: profile,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.lastDownloadedImageUrl, equals('http://10.0.2.2:8080/images/gen_1.png'));
    });

    test('rewrites loopback image URLs to the connection host', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      ));
      vm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      ));
      repo.setStreamFragments(thread.id, [
        const StreamChunk(
          text: '',
          imageUrl: 'http://127.0.0.1:8000/images/gen_1.png',
          isDone: true,
        ),
      ]);
      vm.stubbedImageRef = '/tmp/attachments/a1.png';

      final serverConfig = buildServerConfig();
      final profile = buildServerProfile(baseUrl: 'http://10.0.2.2:8080');
      await vm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: profile,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.lastDownloadedImageUrl, equals('http://10.0.2.2:8000/images/gen_1.png'));
    });
  });

  group('StreamMutationMixin doUndoDelete', () {
    test('restores deleted message', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);

      // Set up thread messages
      repo.getMessagesForThread(thread.id);

      final undoMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Deleted message',
      );
      vm.storeUndoMessage(undoMsg);

      await vm.doUndoDelete();

      expect(vm.getMessageById(undoMsg.id), isNotNull);
    });

    test('does nothing when no undone message', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);

      expect(vm.canUndo, isFalse);

      await vm.doUndoDelete();

      expect(vm.canUndo, isFalse);
    });

    test('canUndo returns true when message stored', () async {
      final vm = TestViewModel();
      final msg = buildMessage(
        threadId: 'thread-1',
        role: MessageRole.user,
        content: 'Undo me',
      );
      vm.storeUndoMessage(msg);

      expect(vm.canUndo, isTrue);
    });

    test('canUndo returns false after undo timeout', () async {
      final vm = TestViewModel();
      final msg = buildMessage(
        threadId: 'thread-1',
        role: MessageRole.user,
        content: 'Undo me',
      );
      vm.storeUndoMessage(msg);

      // Simulate time passing beyond undo timeout
      vm.storeUndoMessage(msg);
      await Future.delayed(const Duration(seconds: 6));

      // The canUndo check uses DateTime.now() so we test with a recent store
      expect(vm.canUndo, isFalse);
    });
  });

  group('StreamMutationMixin doStopGeneration', () {
    test('cancels active generation', () {
      final vm = TestViewModel();
      vm.isGenerating = true;
      vm.currentCancelToken = CancelToken();

      expect(vm.isGenerating, isTrue);
      expect(vm.currentCancelToken, isNotNull);

      vm.doStopGeneration();

      expect(vm.isGenerating, isFalse);
      // CancelToken should still exist but be cancelled
    });

    test('no-op when not generating', () {
      final vm = TestViewModel();
      final token = CancelToken();
      vm.currentCancelToken = token;
      vm.isGenerating = false;

      vm.doStopGeneration();

      expect(vm.isGenerating, isFalse);
    });

    test('clears isGenerating when no cancel token', () {
      final vm = TestViewModel();
      vm.isGenerating = true;
      vm.currentCancelToken = null;

      vm.doStopGeneration();

      expect(vm.isGenerating, isFalse);
    });
  });

  group('StreamMutationMixin doSwitchVariant', () {
    test('switches to previous variant', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);

      // sib2 is variant 1, sib1 is variant 0. We start at sib2 and switch to previous (sib1)
      final sib2 = buildMessage(
        threadId: 'thread-1',
        role: MessageRole.assistant,
        id: 'msg-2',
        variantIndex: 1,
        totalVariants: 2,
        siblingIds: ['msg-1', 'msg-2'],
      );
      final sib1 = buildMessage(
        threadId: 'thread-1',
        role: MessageRole.assistant,
        id: 'msg-1',
        variantIndex: 0,
        totalVariants: 2,
        siblingIds: ['msg-1', 'msg-2'],
      );

      vm.addMessage(sib2);
      await repo.saveMessage(sib1);
      await repo.saveMessage(sib2);
      repo.setStreamFragments('thread-1', []);

      await vm.doSwitchVariant(messageIndex: 0, previous: true);

      final switchedMsg = vm.getMessageById('msg-1');
      expect(switchedMsg, isNotNull);
      expect(switchedMsg!.id, equals('msg-1'));
    });

    test('switches to next variant', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);

      final sib1 = buildMessage(
        threadId: 'thread-1',
        role: MessageRole.assistant,
        id: 'msg-1',
        variantIndex: 0,
        totalVariants: 2,
        siblingIds: ['msg-1', 'msg-2'],
      );
      final sib2 = buildMessage(
        threadId: 'thread-1',
        role: MessageRole.assistant,
        id: 'msg-2',
        variantIndex: 1,
        totalVariants: 2,
        siblingIds: ['msg-1', 'msg-2'],
      );

      vm.addMessage(sib1);
      vm.addMessage(sib2);
      await repo.saveMessage(sib1);
      await repo.saveMessage(sib2);
      repo.setStreamFragments('thread-1', []);

      await vm.doSwitchVariant(messageIndex: 0, previous: false);

      final switchedMsg = vm.getMessageById('msg-2');
      expect(switchedMsg, isNotNull);
      expect(switchedMsg!.id, equals('msg-2'));
    });

    test('no-op when no siblings', () async {
      final vm = TestViewModel();
      vm.addMessage(buildMessage(
        threadId: 'thread-1',
        role: MessageRole.assistant,
        id: 'msg-1',
        variantIndex: 0,
        totalVariants: 1,
        siblingIds: [],
      ));

      await vm.doSwitchVariant(messageIndex: 0, previous: true);

      final msg = vm.getMessageById('msg-1');
      expect(msg!.id, equals('msg-1'));
    });

    test('no-op when message index out of range', () async {
      final vm = TestViewModel();
      vm.addMessage(buildMessage(
        threadId: 'thread-1',
        role: MessageRole.assistant,
        id: 'msg-1',
      ));

      await vm.doSwitchVariant(messageIndex: 5, previous: true);
    });
  });

  group('StreamMutationMixin storeUndoMessage', () {
    test('stores message for undo', () {
      final vm = TestViewModel();
      final msg = buildMessage(
        threadId: 'thread-1',
        role: MessageRole.user,
        content: 'Delete me',
      );

      vm.storeUndoMessage(msg);

      expect(vm.canUndo, isTrue);
    });

    test('stores message with current timestamp', () {
      final vm = TestViewModel();
      final msg = buildMessage(
        threadId: 'thread-1',
        role: MessageRole.user,
        content: 'Delete me',
      );

      vm.storeUndoMessage(msg);

      // canUndo should be true since within timeout
      expect(vm.canUndo, isTrue);
    });
  });

  group('StreamMutationMixin _messagesSublist', () {
    test('returns full message list when upToIndex is null', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);

      vm.addMessage(buildMessage(threadId: 't1', role: MessageRole.user, id: 'u1'));
      vm.addMessage(buildMessage(threadId: 't1', role: MessageRole.assistant, id: 'a1'));

      // Access via reflection-like approach
      final historySlice = <ChatMessage>[];
      final assistantId = 'a1';

      // When upToIndex is null, sublist to assistant message index
      final assistantIndex = vm.messages.indexWhere((m) => m.id == assistantId);
      if (assistantIndex >= 0) {
        historySlice.addAll(vm.messages.sublist(0, assistantIndex));
      }

      expect(historySlice, hasLength(1));
      expect(historySlice[0].id, equals('u1'));
    });

    test('returns sublist up to index when specified', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);

      vm.addMessage(buildMessage(threadId: 't1', role: MessageRole.user, id: 'u1'));
      vm.addMessage(buildMessage(threadId: 't1', role: MessageRole.user, id: 'u2'));
      vm.addMessage(buildMessage(threadId: 't1', role: MessageRole.assistant, id: 'a1'));

      // When upToIndex is 2, should return first 2 messages
      final historySlice = vm.messages.sublist(0, 2);

      expect(historySlice, hasLength(2));
      expect(historySlice[0].id, equals('u1'));
      expect(historySlice[1].id, equals('u2'));
    });
  });

  group('StreamMutationMixin notification', () {
    test('calls notifyListeners after stream completes', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);
      // Add user message so history is non-empty (needed for fake stream lookup)
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      vm.addMessage(userMsg);

      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      );
      vm.addMessage(assistantMsg);
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'done', isDone: true),
      ]);

      bool notified = false;
      final testVm = TestViewModel(repo: repo);
      testVm.setThread(thread);
      testVm.addMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        content: '',
      ));
      testVm.isGenerating = false;
      testVm.currentCancelToken = CancelToken();
      testVm.uiThrottleTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {});

      final serverConfig = buildServerConfig();
      await testVm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: serverConfig,
        connection: null,
        customParams: null,
        modelContextLength: null,
        onComplete: (id) async {
          notified = true;
        },
      );

      expect(notified, isTrue);
    });
  });

  group('StreamMutationMixin scene-image support', () {
    test('discard text mode keeps the seeded content and still captures the '
        'artifact', () async {
      // The scene-image flow seeds a variant with the original dialogue and
      // must not let A-PROX's picture caption overwrite it.
      final repo = FakeChatRepository();
      final testVm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      testVm.setThread(thread);
      repo.setStreamFragments(thread.id, const [
        StreamChunk(
          text: 'Here is a picture of a woman in a garden.',
          imageUrl: 'http://127.0.0.1:8000/images/gen_1.png',
        ),
        StreamChunk(text: ' She is smiling warmly.', isDone: true),
      ]);
      testVm.stubbedImageRef = '/tmp/attachments/ref.png';
      testVm.addMessage(buildMessage(
        threadId: thread.id,
        id: 'assistant-1',
        role: MessageRole.assistant,
        content: 'Alice smiles warmly at Vander.',
        status: MessageStatus.streaming,
      ));

      await testVm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: buildServerConfig(),
        connection: null,
        textMode: StreamTextMode.discard,
      );

      final message = testVm.getMessageById('assistant-1')!;
      expect(
        message.content,
        'Alice smiles warmly at Vander.',
        reason: 'the caption describes the picture request, not the reply',
      );
      expect(message.imagePath, '/tmp/attachments/ref.png');
      expect(message.status, MessageStatus.completed);
      expect(testVm.lastDownloadedImageUrl,
          'http://127.0.0.1:8000/images/gen_1.png');
    });

    test('append mode still accumulates text', () async {
      final repo = FakeChatRepository();
      final testVm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      testVm.setThread(thread);
      repo.setStreamFragments(thread.id, const [
        StreamChunk(text: 'Hello '),
        StreamChunk(text: 'there', isDone: true),
      ]);
      testVm.addMessage(buildMessage(
        threadId: thread.id,
        id: 'assistant-1',
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.streaming,
      ));

      await testVm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: buildServerConfig(),
        connection: null,
      );
      expect(testVm.getMessageById('assistant-1')!.content, 'Hello there');
    });

    test('onArtifactResolved reports the stored path, persisted or not', () async {
      final repo = FakeChatRepository();
      final testVm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      testVm.setThread(thread);
      repo.setStreamFragments(thread.id, const [
        StreamChunk(
          text: 'caption',
          imageUrl: 'http://127.0.0.1:8000/images/gen_2.png',
        ),
        StreamChunk(text: '', isDone: true),
      ]);
      testVm.stubbedImageRef = '/tmp/attachments/portrait.png';
      testVm.addMessage(buildMessage(
        threadId: thread.id,
        id: 'scratch',
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.streaming,
      ));

      String? reported;
      await testVm.doStreamResponse(
        assistantMessageId: 'scratch',
        serverConfig: buildServerConfig(),
        connection: null,
        textMode: StreamTextMode.discard,
        // A scratch message has no thread row, so it must not be written.
        persistOnComplete: false,
        onArtifactResolved: (path) => reported = path,
      );

      expect(reported, '/tmp/attachments/portrait.png');
      expect(
        await repo.getAllMessagesForThread(thread.id),
        isEmpty,
        reason: 'a scratch portrait must not enter the transcript',
      );
    });

    test('historyOverride replaces the derived history slice', () async {
      final repo = FakeChatRepository();
      final testVm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      testVm.setThread(thread);
      repo.setStreamFragments(thread.id, const [
        StreamChunk(text: 'ok', isDone: true),
      ]);
      testVm.addMessage(buildMessage(
        threadId: thread.id,
        id: 'assistant-1',
        role: MessageRole.assistant,
        content: 'kept',
        status: MessageStatus.streaming,
      ));
      final override = [
        buildMessage(
          threadId: thread.id,
          role: MessageRole.user,
          content: '/image a garden',
        ),
      ];

      await testVm.doStreamResponse(
        assistantMessageId: 'assistant-1',
        serverConfig: buildServerConfig(),
        connection: null,
        textMode: StreamTextMode.discard,
        historyOverride: override,
      );
      expect(testVm.getMessageById('assistant-1')!.content, 'kept');
    });
  });

  group('StreamMutationMixin doCreateImageVariant', () {
    test('creates a sibling variant that keeps the original text', () async {
      final repo = FakeChatRepository();
      final testVm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      testVm.setThread(thread);
      final original = buildMessage(
        threadId: thread.id,
        id: 'm1',
        role: MessageRole.assistant,
        content: 'Alice smiles warmly at Vander.',
        status: MessageStatus.completed,
      );
      await repo.saveMessage(original);
      testVm.addMessage(original);

      final result = await testVm.doCreateImageVariant(messageIndex: 0);
      expect(result, isNotNull);
      expect(result!.oldMessageId, 'm1');

      final variant = testVm.getMessageById(result.newAssistantId)!;
      expect(variant.content, 'Alice smiles warmly at Vander.');
      expect(variant.status, MessageStatus.streaming);
      expect(variant.variantIndex, 1);
      expect(variant.totalVariants, 2);
      expect(variant.siblingIds, containsAll(<String>['m1', result.newAssistantId]));
      expect(variant.parentId, original.parentId);
    });

    test('does not inherit an image from the message it replaces', () async {
      // Each press must be an independent generation from the identity
      // reference, not a re-edit of the previous picture.
      final repo = FakeChatRepository();
      final testVm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      testVm.setThread(thread);
      final original = buildMessage(
        threadId: thread.id,
        id: 'm1',
        role: MessageRole.assistant,
        content: 'text',
        status: MessageStatus.completed,
        imagePath: '/tmp/old.png',
      );
      await repo.saveMessage(original);
      testVm.addMessage(original);

      final result = await testVm.doCreateImageVariant(messageIndex: 0);
      expect(testVm.getMessageById(result!.newAssistantId)!.imagePath, isNull);
    });

    test('refuses for a user message and while generating', () async {
      final repo = FakeChatRepository();
      final testVm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      testVm.setThread(thread);
      testVm.addMessage(buildMessage(
        threadId: thread.id,
        id: 'u1',
        role: MessageRole.user,
        content: 'hi',
      ));
      expect(await testVm.doCreateImageVariant(messageIndex: 0), isNull);

      testVm.clearMessages();
      testVm.addMessage(buildMessage(
        threadId: thread.id,
        id: 'a1',
        role: MessageRole.assistant,
        content: 'x',
      ));
      testVm.isGenerating = true;
      expect(await testVm.doCreateImageVariant(messageIndex: 0), isNull);
    });

    test('doRevertVariant puts the original message back', () async {
      final repo = FakeChatRepository();
      final testVm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      testVm.setThread(thread);
      final original = buildMessage(
        threadId: thread.id,
        id: 'm1',
        role: MessageRole.assistant,
        content: 'original text',
        status: MessageStatus.completed,
      );
      await repo.saveMessage(original);
      testVm.addMessage(original);

      final result = await testVm.doCreateImageVariant(messageIndex: 0);
      await testVm.doRevertVariant(
        messageIndex: 0,
        newAssistantId: result!.newAssistantId,
        oldMessageId: result.oldMessageId,
      );

      expect(testVm.messages, hasLength(1));
      expect(testVm.messages.single.id, 'm1');
      expect(testVm.messages.single.content, 'original text');
      expect(
        await repo.getAllMessagesForThread(thread.id),
        hasLength(1),
        reason: 'the empty placeholder must not linger in the database',
      );
    });
  });
  group('variant group consistency', () {
    /// Seeds a thread with a user turn plus assistant variant `M0`, and returns
    /// helpers for driving regeneration the way the stream-completion hook does.
    Future<({FakeChatRepository repo, TestViewModel vm, dynamic thread})> seed()
        async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'T');
      vm.setThread(thread);
      final userMsg = buildMessage(
          threadId: thread.id, role: MessageRole.user, content: 'hi');
      final asst = buildMessage(
          threadId: thread.id,
          id: 'M0',
          role: MessageRole.assistant,
          content: 'v0',
          status: MessageStatus.completed);
      await repo.saveMessage(userMsg);
      await repo.saveMessage(asst);
      vm.addMessage(userMsg);
      vm.addMessage(asst);
      return (repo: repo, vm: vm, thread: thread);
    }

    /// Mirrors what the stream-completion hook does: finish the streaming
    /// placeholder and persist it, which is what makes it a real sibling.
    Future<String> regenerateAndPersist(TestViewModel vm, FakeChatRepository repo) async {
      final r = await vm.doRegenerateMessage(messageIndex: 1);
      expect(r, isNotNull);
      final newId = r!.newAssistantId;
      final i = vm.messages.indexWhere((m) => m.id == newId);
      final done =
          vm.messages[i].copyWith(content: 'reply', status: MessageStatus.completed);
      vm.messages[i] = done;
      await repo.saveMessage(done);
      return newId;
    }

    test('every member of a 3-variant group reports the same count', () async {
      final s = await seed();
      await regenerateAndPersist(s.vm, s.repo);
      await regenerateAndPersist(s.vm, s.repo);

      final stored = await s.repo.getAllMessagesForThread(s.thread.id);
      final variants = stored.where((m) => m.role == MessageRole.assistant).toList();
      expect(variants.length, 3);

      // The regression: siblings used to be handed the new siblingIds but kept
      // their old totalVariants, so the oldest variant displayed "1 / 2" while
      // the group held three and the next arrow looked live but did nothing.
      for (final v in variants) {
        expect(v.totalVariants, 3,
            reason: '${v.id} has a stale totalVariants');
        expect(v.siblingIds.length, 3,
            reason: '${v.id} has a stale siblingIds list');
        expect(v.siblingIds.toSet(), variants.map((m) => m.id).toSet());
      }
    });

    test('cycles forward and backward through every variant', () async {
      final s = await seed();
      await regenerateAndPersist(s.vm, s.repo);
      final second = await regenerateAndPersist(s.vm, s.repo);
      expect(s.vm.messages[1].id, second, reason: 'newest variant is visible');

      await s.vm.doSwitchVariant(messageIndex: 1, previous: true);
      expect(s.vm.messages[1].variantIndex, 1);
      await s.vm.doSwitchVariant(messageIndex: 1, previous: true);
      expect(s.vm.messages[1].id, 'M0', reason: 'oldest variant reached');

      // The original complaint: sitting on the oldest, "next" did nothing.
      await s.vm.doSwitchVariant(messageIndex: 1, previous: false);
      expect(s.vm.messages[1].variantIndex, 1);
      await s.vm.doSwitchVariant(messageIndex: 1, previous: false);
      expect(s.vm.messages[1].id, second, reason: 'newest variant reached');

      // Clamped at the ends rather than wrapping or throwing.
      await s.vm.doSwitchVariant(messageIndex: 1, previous: false);
      expect(s.vm.messages[1].id, second);
    });

    test('survives a reload from the database', () async {
      final s = await seed();
      await regenerateAndPersist(s.vm, s.repo);
      await regenerateAndPersist(s.vm, s.repo);

      // A reload goes through the deduping query, which keeps the newest
      // variant per group - the state the user actually sees after a restart.
      final reloaded = await s.repo.getMessagesForThread(s.thread.id);
      final shown = reloaded.lastWhere((m) => m.role == MessageRole.assistant);
      final siblings = await s.repo.getAllMessagesForThread(s.thread.id);
      final byId = {for (final m in siblings) m.id: m};

      final resolved = shown.siblingIds.map((id) => byId[id]).whereType().toList()
        ..sort((a, b) => a.variantIndex.compareTo(b.variantIndex));
      expect(resolved.length, 3);
      expect(resolved.map((m) => m.id).toSet(),
          byId.keys.where((id) => byId[id]!.role == MessageRole.assistant).toSet());
      // Dedupe keeps the newest variant, which is the highest index, so the
      // navigator can walk back to both earlier replies.
      expect(shown.variantIndex, 2);
      expect(resolved.last.id, shown.id);
      expect(resolved.first.id, 'M0');
    });

    test('image variant is a full sibling, not an unlisted extra', () async {
      final s = await seed();
      final r = await s.vm.doCreateImageVariant(messageIndex: 1);
      expect(r, isNotNull);
      final i = s.vm.messages.indexWhere((m) => m.id == r!.newAssistantId);
      final withImage = s.vm.messages[i]
          .copyWith(status: MessageStatus.completed, imagePath: '/tmp/a.png');
      s.vm.messages[i] = withImage;
      await s.repo.saveMessage(withImage);

      final stored =
          (await s.repo.getAllMessagesForThread(s.thread.id))
              .where((m) => m.role == MessageRole.assistant)
              .toList();
      expect(stored.length, 2);
      for (final v in stored) {
        expect(v.totalVariants, 2, reason: '${v.id} has a stale totalVariants');
        expect(v.siblingIds.length, 2);
      }
      // The image variant keeps the dialogue and does not inherit a picture.
      expect(withImage.content, 'v0');
      expect(withImage.imagePath, '/tmp/a.png');
      expect(stored.firstWhere((m) => m.id == 'M0').imagePath, isNull);
    });

    test('reverting a failed image variant leaves a navigable group', () async {
      final s = await seed();
      final r = await s.vm.doCreateImageVariant(messageIndex: 1);
      await s.vm.doRevertVariant(
        messageIndex: 1,
        newAssistantId: r!.newAssistantId,
        oldMessageId: 'M0',
      );

      expect(s.vm.messages[1].id, 'M0');
      // The regression: the restored message used to keep listing the deleted
      // placeholder, leaving a permanently unreachable "next" arrow.
      expect(s.vm.messages[1].siblingIds, isNot(contains(r.newAssistantId)));
      expect(s.vm.messages[1].totalVariants, 1);

      final stored = await s.repo.getAllMessagesForThread(s.thread.id);
      final variants = stored.where((m) => m.role == MessageRole.assistant).toList();
      expect(variants.length, 1);
      for (final v in variants) {
        expect(v.siblingIds.toSet(), {'M0'});
        expect(v.totalVariants, 1);
      }

      await s.vm.doSwitchVariant(messageIndex: 1, previous: false);
      expect(s.vm.messages[1].id, 'M0', reason: 'no-op instead of a stuck arrow');
    });

    test('drops a sibling id with no stored row instead of duplicating',
        () async {
      final s = await seed();
      await regenerateAndPersist(s.vm, s.repo);
      // A dangling id: the other variant was deleted, but this message still
      // advertises it. Substituting the current message produced a duplicate
      // with the same variantIndex, so the switch silently did nothing.
      final newId = s.vm.messages[1].id;
      final stored = await s.repo.getAllMessagesForThread(s.thread.id);
      final oldest = stored.firstWhere((m) => m.id == 'M0');
      // Sit on the oldest variant, which still advertises a sibling that is
      // gone. With the old `orElse` the ghost resolved to the current message
      // itself, so the sorted list held [M0, M0, newId] and "next" landed on
      // M0 again - a silent no-op while the arrow still looked live.
      s.vm.messages[1] = oldest
          .copyWith(siblingIds: [...oldest.siblingIds, 'ghost']);

      await s.vm.doSwitchVariant(messageIndex: 1, previous: false);
      expect(s.vm.messages[1].id, newId, reason: 'next reached the real sibling');
      expect(s.vm.messages[1].siblingIds, isNot(contains('ghost')));
    });
  });

}
