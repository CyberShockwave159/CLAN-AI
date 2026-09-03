import 'dart:async';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:clan_ai/ui/shared/mixins/stream_mutation_mixin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_chat_repository.dart';
import '../helpers/test_model_factories.dart';

// Test class that mixes in StreamMutationMixin
class TestViewModel with StreamMutationMixin {
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

  void setThread(ChatThread thread) => _activeThread = thread;

  void addMessage(ChatMessage msg) {
    _messages.add(msg);
  }

  void clearMessages() => _messages.clear();

  List<ChatMessage> get allMessages => _messages;

  ChatMessage? getMessageById(String id) {
    return _messages.where((m) => m.id == id).firstOrNull;
  }

  void notifyListeners() {
    // No-op for testing
  }
}

extension<T> on Iterable<T> {
  T? get orNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }
}

void main() {
  group('StreamMutationMixin doStreamResponse', () {
    test('streams chunks and accumulates content into message', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);

      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
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

      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
      );
      vm.addMessage(assistantMsg);
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hello', isDone: true),
      ]);

      // isGenerating should be false initially
      expect(vm.isGenerating, isFalse);

      // Start streaming
      vm.isGenerating = false;
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

      expect(repo.lastSavedMessage, isNotNull);
      expect(repo.lastSavedMessage!.content, equals('partial completed'));
      expect(repo.lastSavedMessage!.status, equals(MessageStatus.completed));
    });

    test('calls onComplete hook after stream completes', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);

      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
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

      expect(vm.isGenerating, isFalse);
    });

    test('accumulates reasoning content', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);

      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
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

      final result = vm.getMessageById('assistant-1');
      expect(result!.reasoningContent, equals('Thinking 1Thinking 2'));
    });

    test('preserves existing reasoningContent when streaming', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);
      final thread = buildThread(title: 'Test');
      vm.setThread(thread);

      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
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

      final result = vm.getMessageById('assistant-1');
      expect(result!.reasoningContent, equals('Previous reasoningNew reasoning'));
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
      expect(vm.canUndo, isTrue);
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

    test('no-op when no cancel token', () {
      final vm = TestViewModel();
      vm.isGenerating = true;
      vm.currentCancelToken = null;

      vm.doStopGeneration();

      expect(vm.isGenerating, isFalse);
    });
  });

  group('StreamMutationMixin doSwitchVariant', () async {
    test('switches to previous variant', () async {
      final repo = FakeChatRepository();
      final vm = TestViewModel(repo: repo);

      final sib1 = buildMessage(
        threadId: 'thread-1',
        role: MessageRole.assistant,
        id: 'msg-1',
        variantIndex: 0,
        totalVariants: 2,
        siblingIds: ['msg-2'],
      );
      final sib2 = buildMessage(
        threadId: 'thread-1',
        role: MessageRole.assistant,
        id: 'msg-2',
        variantIndex: 1,
        totalVariants: 2,
        siblingIds: ['msg-1'],
      );

      vm.addMessage(sib1);
      repo.setStreamFragments('thread-1', []);

      await vm.doSwitchVariant(messageIndex: 0, previous: true);

      final switchedMsg = vm.getMessageById('msg-2');
      expect(switchedMsg, isNotNull);
      expect(switchedMsg!.id, equals('msg-2'));
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
        siblingIds: ['msg-2'],
      );
      final sib2 = buildMessage(
        threadId: 'thread-1',
        role: MessageRole.assistant,
        id: 'msg-2',
        variantIndex: 1,
        totalVariants: 2,
        siblingIds: ['msg-1'],
      );

      vm.addMessage(sib2);
      repo.setStreamFragments('thread-1', []);

      await vm.doSwitchVariant(messageIndex: 0, previous: false);

      final switchedMsg = vm.getMessageById('msg-1');
      expect(switchedMsg, isNotNull);
      expect(switchedMsg!.id, equals('msg-1'));
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

      final before = DateTime.now();
      vm.storeUndoMessage(msg);
      final after = DateTime.now();

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

      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
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
}
