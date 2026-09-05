import 'dart:convert';

import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_chat_repository.dart';
import '../helpers/test_model_factories.dart';

/// Tests: Settings persistence across sessions.
void main() {
  late FakeChatRepository repo;

  setUp(() {
    repo = FakeChatRepository();
  });

  test('system prompt persists across thread updates', () async {
    final thread = await repo.createThread(
      title: 'Test',
      systemPrompt: 'Custom prompt',
    );

    // Update system prompt
    final updated = thread.copyWith(systemPrompt: 'New custom prompt');
    await repo.updateThread(updated);

    final reloaded = await repo.getThreads();
    expect(
      reloaded.firstWhere((t) => t.id == thread.id).systemPrompt,
      equals('New custom prompt'),
    );
  });

  test('modelId persists across updates', () async {
    final thread = await repo.createThread(
      title: 'Test',
      modelId: 'llama-3.2',
    );

    final reloaded = await repo.getThreads();
    expect(
      reloaded.firstWhere((t) => t.id == thread.id).modelId,
      equals('llama-3.2'),
    );
  });

  test('thread metadata (pinned, branch) persists', () async {
    final thread = await repo.createThread(title: 'Test');

    // Pin thread
    final pinned = thread.copyWith(isPinned: true);
    await repo.updateThread(pinned);

    // Branch thread
    final branched = pinned.copyWith(branchFromThreadId: 'parent-thread');
    await repo.updateThread(branched);

    final reloaded = await repo.getThreads();
    final found = reloaded.firstWhere((t) => t.id == thread.id);
    expect(found.isPinned, isTrue);
    expect(found.branchFromThreadId, equals('parent-thread'));
  });

  test('conversation export format matches thread content', () async {
    final thread = await repo.createThread(
      title: 'Export Test',
      systemPrompt: 'System prompt',
    );

    await repo.saveMessage(buildMessage(
      id: 'user-msg-1',
      threadId: thread.id,
      role: MessageRole.user,
      content: 'User message',
    ));
    await repo.saveMessage(buildMessage(
      id: 'assistant-msg-1',
      threadId: thread.id,
      role: MessageRole.assistant,
      content: 'Assistant message',
    ));

    final messages = await repo.getMessagesForThread(thread.id);
    final txt = ConversationExport.toTxt(thread, messages);
    final json = ConversationExport.toJson(thread, messages);

    expect(txt, contains('=== Export Test ==='));
    expect(txt, contains('--- System Prompt ---'));
    expect(txt, contains('User message'));
    expect(txt, contains('Assistant message'));

    // JSON should be valid
    expect(() => jsonDecode(json), returnsNormally);
  });

  test('thread title updates persist', () async {
    final thread = await repo.createThread(title: 'Original');

    final updated = thread.copyWith(title: 'Updated Title');
    await repo.updateThread(updated);

    final reloaded = await repo.getThreads();
    expect(
      reloaded.firstWhere((t) => t.id == thread.id).title,
      equals('Updated Title'),
    );
  });

  test('thread updatedAt updates on modification', () async {
    final original = await repo.createThread(title: 'Test');
    final originalUpdated = original.updatedAt;

    await Future.delayed(const Duration(milliseconds: 10));

    final updated = original.copyWith(title: 'Updated', updatedAt: DateTime.now());
    await repo.updateThread(updated);

    final reloaded = await repo.getThreads();
    expect(
      reloaded.firstWhere((t) => t.id == original.id).updatedAt.isAfter(originalUpdated),
      isTrue,
    );
  });

  test('thread customParams persist', () async {
    final thread = await repo.createThread(
      title: 'Test',
      customParams: const GenerationParams(temperature: 0.7),
    );

    final reloaded = await repo.getThreads();
    final found = reloaded.firstWhere((t) => t.id == thread.id);
    expect(found.customParams, isNotNull);
    expect(found.customParams!.temperature, equals(0.7));
  });

  test('multiple threads maintain separate state', () async {
    final thread1 = await repo.createThread(title: 'Thread 1');
    final thread2 = await repo.createThread(title: 'Thread 2');

    final updated1 = thread1.copyWith(systemPrompt: 'Prompt 1');
    final updated2 = thread2.copyWith(systemPrompt: 'Prompt 2');
    await repo.updateThread(updated1);
    await repo.updateThread(updated2);

    final threads = await repo.getThreads();
    final t1 = threads.firstWhere((t) => t.id == thread1.id);
    final t2 = threads.firstWhere((t) => t.id == thread2.id);

    expect(t1.systemPrompt, equals('Prompt 1'));
    expect(t2.systemPrompt, equals('Prompt 2'));
  });
}
