import 'dart:async';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:clan_ai/ui/features/chat/view_models/chat_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_chat_repository.dart';
import '../helpers/test_model_factories.dart';

/// Integration test: Full assistant chat flow without network.
void main() {
  late FakeChatRepository repo;
  late ChatViewModel vm;

  setUp(() {
    repo = FakeChatRepository();
    vm = ChatViewModel(chatRepository: repo);
  });

  tearDown(() {
    vm.dispose();
  });

  test('Full assistant flow: create thread, send message, regenerate, edit, branch, delete', () async {
    // 1. Create a new thread
    final thread = await vm.createNewThread(title: 'My Chat');
    expect(vm.activeThread, isNotNull);
    expect(vm.activeThread!.title, equals('My Chat'));
    expect(vm.threads, hasLength(1));

    // 2. Set up stream response for send/re-generate/edit
    fakeStreamSetup(repo, thread.id, 'Response');

    // 3. Send a user message
    await vm.sendMessage(
      prompt: 'Hello, assistant!',
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    expect(vm.messages.length, greaterThanOrEqualTo(2));
    expect(vm.messages.where((m) => m.role == MessageRole.user).length, equals(1));

    // 4. Regenerate the assistant response
    fakeStreamSetup(repo, thread.id, 'Regenerated response');

    await vm.regenerateMessage(
      messageIndex: 1,
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    // Verify variant increased
    final regeneratedMsg = vm.messages[1];
    expect(regeneratedMsg.variantIndex, equals(1));
    expect(regeneratedMsg.totalVariants, equals(2));
    expect(regeneratedMsg.siblingIds, hasLength(1));

    // 5. Edit the user prompt (branch conversation)
    final userMsgIndex = 0;
    fakeStreamSetup(repo, thread.id, 'Branch response');

    await vm.editUserPrompt(
      messageIndex: userMsgIndex,
      newContent: 'Edited prompt',
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    // The message content should be updated
    final editedUserMsg = vm.messages.where((m) => m.content == 'Edited prompt');
    expect(editedUserMsg, isNotEmpty);

    // 6. Export the conversation
    final exportPath = await vm.exportThread(ExportFormat.json);
    expect(exportPath, isNotNull);

    // 7. Delete a message (user message triggers thread deletion)
    final userMsg = vm.messages.firstWhere((m) => m.role == MessageRole.user);
    final wasThreadDeleted = await vm.deleteMessage(
      messageIndex: 0,
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    expect(wasThreadDeleted, isTrue);

    // 8. Undo the delete
    await repo.saveMessage(userMsg);
    await vm.undoDelete();
    expect(vm.canUndo, isFalse);
  });

  test('Multi-turn chat flow with regeneration', () async {
    // Create thread
    final thread = await vm.createNewThread(title: 'Multi-turn');
    fakeStreamSetup(repo, thread.id, 'Hi there!');

    // Send message 1
    await vm.sendMessage(
      prompt: 'First question',
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );
    expect(vm.messages.length, greaterThanOrEqualTo(2));

    // Send message 2
    fakeStreamSetup(repo, thread.id, 'Second response');
    await vm.sendMessage(
      prompt: 'Follow up question',
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );
    expect(vm.messages.length, greaterThanOrEqualTo(4));

    // Regenerate last assistant response
    fakeStreamSetup(repo, thread.id, 'New second response');
    await vm.regenerateMessage(
      messageIndex: 3,
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    expect(vm.messages[3].variantIndex, equals(1));
    expect(vm.messages[3].totalVariants, equals(2));
  });

  test('Branching conversation creates new thread', () async {
    // Create original thread
    final originalThread = await vm.createNewThread(title: 'Original');
    final userMsg = buildMessage(
      threadId: originalThread.id,
      role: MessageRole.user,
      id: 'user-1',
    );
    final assistantMsg = buildMessage(
      threadId: originalThread.id,
      role: MessageRole.assistant,
      id: 'assistant-1',
      parentId: 'user-1',
    );
    vm.threads; [originalThread];
    vm.activeThread; originalThread;
    vm.messages = [userMsg, assistantMsg];

    fakeStreamSetup(repo, originalThread.id, 'Branch response');

    // Branch from user message
    await vm.branchConversation(
      messageIndex: 0,
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    // Should have two threads now
    expect(vm.threads, hasLength(2));
    expect(vm.activeThread, isNotNull);
    expect(vm.activeThread?.branchFromThreadId, equals(originalThread.id));
  });

  test('Message deletion with regeneration flow', () async {
    final thread = await vm.createNewThread(title: 'Deletion test');
    final userMsg = buildMessage(
      threadId: thread.id,
      role: MessageRole.user,
      id: 'user-1',
    );
    final assistantMsg = buildMessage(
      threadId: thread.id,
      role: MessageRole.assistant,
      id: 'assistant-1',
      parentId: 'user-1',
    );
    vm.activeThread; thread;
    vm.messages = [userMsg, assistantMsg];

    fakeStreamSetup(repo, thread.id, 'New response');

    // Delete assistant message (triggers regeneration)
    final wasThreadDeleted = await vm.deleteMessage(
      messageIndex: 1,
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    expect(wasThreadDeleted, isFalse);
    expect(vm.messages.where((m) => m.role == MessageRole.assistant).length, greaterThanOrEqualTo(1));
  });

  test('Export with multiple messages', () async {
    final thread = await vm.createNewThread(title: 'Export test');
    vm.activeThread; thread;
    vm.messages = [
      buildMessage(role: MessageRole.user, content: 'User message'),
      buildMessage(role: MessageRole.assistant, content: 'Assistant message'),
      buildMessage(role: MessageRole.user, content: 'Follow up'),
      buildMessage(role: MessageRole.assistant, content: 'Final response'),
    ];

    final txtPath = await vm.exportThread(ExportFormat.txt);
    expect(txtPath, isNotNull);

    final jsonPath = await vm.exportThread(ExportFormat.json);
    expect(jsonPath, isNotNull);
  });

  test('Thread renaming persists', () async {
    final thread = await vm.createNewThread(title: 'Original');
    vm.threads; [thread];
    vm.activeThread; thread;

    await vm.renameThread(thread.id, 'Renamed');

    expect(vm.activeThread?.title, equals('Renamed'));

    // Verify persistence
    final threads = await repo.getThreads();
    expect(threads.firstWhere((t) => t.id == thread.id).title, equals('Renamed'));
  });

  test('System prompt update persists', () async {
    final thread = await vm.createNewThread(title: 'Thread');
    vm.activeThread; thread;

    await vm.updateActiveThreadSystemPrompt('Custom system prompt');

    expect(vm.activeThread?.systemPrompt, equals('Custom system prompt'));

    final threads = await repo.getThreads();
    expect(
      threads.firstWhere((t) => t.id == thread.id).systemPrompt,
      equals('Custom system prompt'),
    );
  });
}

void fakeStreamSetup(FakeChatRepository repo, String threadId, String response) {
  repo.setStreamFragments(threadId, [
    const StreamChunk(text: '', isDone: false),
    StreamChunk(text: response, isDone: true),
  ]);
}
