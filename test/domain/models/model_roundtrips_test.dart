import 'dart:convert';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/persona_template.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clan_ai/core/constants/app_constants.dart';

void main() {
  group('ChatThread model roundtrip', () {
    test('toMap/fromMap preserves all fields', () {
      final original = ChatThread(
        id: 'test-thread-id',
        title: 'My Chat',
        systemPrompt: 'You are helpful.',
        modelId: 'my-model',
        isPinned: true,
        branchFromThreadId: 'parent-thread',
        characterId: 'char-123',
      );

      final map = original.toMap();
      final restored = ChatThread.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.title, equals(original.title));
      expect(restored.systemPrompt, equals(original.systemPrompt));
      expect(restored.modelId, equals(original.modelId));
      expect(restored.isPinned, equals(original.isPinned));
      expect(restored.branchFromThreadId, equals(original.branchFromThreadId));
      expect(restored.characterId, equals(original.characterId));
      expect(restored.createdAt, isNotNull);
      expect(restored.updatedAt, isNotNull);
    });

    test('toMap/fromMap handles null optional fields', () {
      final original = ChatThread(title: 'Default Thread');

      final map = original.toMap();
      final restored = ChatThread.fromMap(map);

      expect(restored.systemPrompt, isNull);
      expect(restored.modelId, isNull);
      expect(restored.isPinned, isFalse);
      expect(restored.branchFromThreadId, isNull);
      expect(restored.characterId, isNull);
      expect(restored.title, equals('Default Thread'));
    });

    test('toMap/fromMap with customParams serializes JSON', () {
      final params = GenerationParams(
        temperature: 0.7,
        topP: 0.9,
        maxTokens: 2048,
      );
      final original = ChatThread(
        title: 'Params Thread',
        customParams: params,
      );

      final map = original.toMap();
      expect(map['custom_params'], isNotNull);

      final restored = ChatThread.fromMap(map);
      expect(restored.customParams, isNotNull);
      expect(restored.customParams!.temperature, equals(0.7));
      expect(restored.customParams!.topP, equals(0.9));
      expect(restored.customParams!.maxTokens, equals(2048));
    });

    test('copyWith creates new instance with updated fields', () {
      final original = ChatThread(title: 'Old Title');
      final updated = original.copyWith(title: 'New Title', isPinned: true);

      expect(updated.title, equals('New Title'));
      expect(updated.isPinned, isTrue);
      expect(updated.id, equals(original.id));
      expect(updated.createdAt, equals(original.createdAt));
    });

    test('copyWith preserves unchanged fields', () {
      final original = ChatThread(
        title: 'Title',
        systemPrompt: 'System',
        modelId: 'model',
        isPinned: true,
        branchFromThreadId: 'parent',
        characterId: 'char',
      );
      final copied = original.copyWith();

      expect(copied.title, equals(original.title));
      expect(copied.systemPrompt, equals(original.systemPrompt));
      expect(copied.modelId, equals(original.modelId));
      expect(copied.isPinned, equals(original.isPinned));
      expect(copied.branchFromThreadId, equals(original.branchFromThreadId));
      expect(copied.characterId, equals(original.characterId));
    });

    test('default values use current DateTime', () {
      final now = DateTime.now();
      final thread = ChatThread();

      expect(thread.title, equals('New Chat'));
      expect(thread.createdAt.isAfter(now.subtract(const Duration(minutes: 1))), isTrue);
      expect(thread.updatedAt.isAfter(now.subtract(const Duration(minutes: 1))), isTrue);
    });

    test('UUID is generated when no id provided', () {
      final thread = ChatThread();
      expect(thread.id, isNotNull);
      expect(thread.id.isNotEmpty, isTrue);
    });

    test('fromMap handles missing date strings gracefully', () {
      final map = <String, dynamic>{
        'id': 'test',
        'title': 'Test',
      };
      final thread = ChatThread.fromMap(map);
      expect(thread.id, equals('test'));
      expect(thread.title, equals('Test'));
      expect(thread.createdAt, isNotNull);
      expect(thread.updatedAt, isNotNull);
    });
  });

  group('ChatMessage model roundtrip', () {
    test('toMap/fromMap preserves all fields', () {
      final original = ChatMessage(
        id: 'msg-1',
        threadId: 'thread-1',
        parentId: 'parent-1',
        role: MessageRole.assistant,
        content: 'Hello world',
        status: MessageStatus.completed,
        tokensPerSecond: 42.5,
        totalTokens: 100,
        timeToFirstTokenMs: 500,
        generationTimeSec: 2.5,
        errorMessage: null,
        variantIndex: 1,
        totalVariants: 3,
        siblingIds: ['sibling-1', 'sibling-2'],
        isEdited: true,
        ragMemoryCount: 2,
        reasoningContent: 'Step-by-step reasoning here.',
      );

      final map = original.toMap();
      final restored = ChatMessage.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.threadId, equals(original.threadId));
      expect(restored.parentId, equals(original.parentId));
      expect(restored.role, equals(MessageRole.assistant));
      expect(restored.content, equals(original.content));
      expect(restored.status, equals(MessageStatus.completed));
      expect(restored.tokensPerSecond, equals(42.5));
      expect(restored.totalTokens, equals(100));
      expect(restored.timeToFirstTokenMs, equals(500));
      expect(restored.generationTimeSec, equals(2.5));
      expect(restored.variantIndex, equals(1));
      expect(restored.totalVariants, equals(3));
      expect(restored.siblingIds, hasLength(2));
      expect(restored.siblingIds, containsAll(['sibling-1', 'sibling-2']));
      expect(restored.isEdited, isTrue);
      expect(restored.ragMemoryCount, equals(2));
      expect(restored.reasoningContent, equals('Step-by-step reasoning here.'));
    });

    test('fromMap parses empty sibling_ids as empty list', () {
      final map = <String, dynamic>{
        'id': 'm1',
        'thread_id': 't1',
        'role': 'user',
        'content': 'Hi',
        'status': 'completed',
        'sibling_ids': '',
        'created_at': DateTime.now().toIso8601String(),
      };
      final msg = ChatMessage.fromMap(map);
      expect(msg.siblingIds, isEmpty);
    });

    test('fromMap parses sibling_ids comma-separated', () {
      final map = <String, dynamic>{
        'id': 'm1',
        'thread_id': 't1',
        'role': 'user',
        'content': 'Hi',
        'status': 'completed',
        'sibling_ids': 'a,b,c',
        'created_at': DateTime.now().toIso8601String(),
      };
      final msg = ChatMessage.fromMap(map);
      expect(msg.siblingIds, hasLength(3));
    });

    test('fromMap handles unknown status as completed', () {
      final map = <String, dynamic>{
        'id': 'm1',
        'thread_id': 't1',
        'role': 'user',
        'content': 'Hi',
        'status': 'unknown_status',
        'created_at': DateTime.now().toIso8601String(),
      };
      final msg = ChatMessage.fromMap(map);
      expect(msg.status, equals(MessageStatus.completed));
    });

    test('fromMap handles missing status as completed', () {
      final map = <String, dynamic>{
        'id': 'm1',
        'thread_id': 't1',
        'role': 'user',
        'content': 'Hi',
        'created_at': DateTime.now().toIso8601String(),
      };
      final msg = ChatMessage.fromMap(map);
      expect(msg.status, equals(MessageStatus.completed));
    });

    test('copyWith updates individual fields', () {
      final original = ChatMessage(
        threadId: 't1',
        role: MessageRole.user,
        content: 'Hello',
      );
      final updated = original.copyWith(
        content: 'Hello world',
        isEdited: true,
      );

      expect(updated.content, equals('Hello world'));
      expect(updated.isEdited, isTrue);
      expect(updated.id, equals(original.id));
      expect(updated.role, equals(MessageRole.user));
    });

    test('MessageRole values map correctly', () {
      expect(MessageRole.system.value, equals('system'));
      expect(MessageRole.user.value, equals('user'));
      expect(MessageRole.assistant.value, equals('assistant'));
    });

    test('MessageRole.fromString parses correctly', () {
      expect(MessageRole.fromString('system'), equals(MessageRole.system));
      expect(MessageRole.fromString('user'), equals(MessageRole.user));
      expect(MessageRole.fromString('assistant'), equals(MessageRole.assistant));
      expect(MessageRole.fromString('unknown'), equals(MessageRole.assistant));
    });

    test('all MessageStatus values exist', () {
      expect(MessageStatus.values, contains(MessageStatus.idle));
      expect(MessageStatus.values, contains(MessageStatus.sending));
      expect(MessageStatus.values, contains(MessageStatus.streaming));
      expect(MessageStatus.values, contains(MessageStatus.completed));
      expect(MessageStatus.values, contains(MessageStatus.error));
    });

    test('reasoningContent defaults to empty string', () {
      final msg = ChatMessage(
        threadId: 't1',
        role: MessageRole.user,
        content: 'Hi',
      );
      expect(msg.reasoningContent, equals(''));
    });

    test('toMap preserves reasoningContent', () {
      final msg = ChatMessage(
        threadId: 't1',
        role: MessageRole.user,
        content: 'Hi',
        reasoningContent: 'Thinking process...',
      );
      final map = msg.toMap();
      expect(map['reasoning_content'], equals('Thinking process...'));
    });
  });

  group('CharacterProfile model roundtrip', () {
    test('toMap/fromMap preserves all fields', () {
      final original = CharacterProfile(
        id: 'char-1',
        name: 'Test Character',
        personality: 'Brave and cunning',
        firstMessage: 'Welcome, traveler.',
        setting: 'A medieval fantasy world',
        userPersona: 'A wandering knight',
        isFavorite: true,
        systemPrompt: 'You are a medieval character.',
        postHistoryInstructions: 'Keep responses in character.',
        alternateGreetings: ['Hi!', 'Hello there!', 'Greetings!'],
      );

      final map = original.toMap();
      final restored = CharacterProfile.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.personality, equals(original.personality));
      expect(restored.firstMessage, equals(original.firstMessage));
      expect(restored.setting, equals(original.setting));
      expect(restored.userPersona, equals(original.userPersona));
      expect(restored.isFavorite, equals(original.isFavorite));
      expect(restored.systemPrompt, equals(original.systemPrompt));
      expect(restored.postHistoryInstructions, equals(original.postHistoryInstructions));
      expect(restored.alternateGreetings, hasLength(3));
      expect(restored.alternateGreetings, containsAll(['Hi!', 'Hello there!', 'Greetings!']));
    });

    test('toMap/fromMap serializes alternateGreetings as JSON', () {
      final original = CharacterProfile(
        name: 'Test',
        personality: 'Test',
        firstMessage: 'Test',
        alternateGreetings: ['Alt1', 'Alt2'],
      );

      final map = original.toMap();
      expect(map['alternate_greetings'], isNotNull);

      final restored = CharacterProfile.fromMap(map);
      expect(restored.alternateGreetings, hasLength(2));
    });

    test('fromMap handles missing alternate_greetings', () {
      final map = <String, dynamic>{
        'id': 'c1',
        'name': 'Test',
        'personality': 'Test',
        'first_message': 'Test',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      final char = CharacterProfile.fromMap(map);
      expect(char.alternateGreetings, isEmpty);
    });

    test('fromMap handles empty alternate_greetings string', () {
      final map = <String, dynamic>{
        'id': 'c1',
        'name': 'Test',
        'personality': 'Test',
        'first_message': 'Test',
        'alternate_greetings': '',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      final char = CharacterProfile.fromMap(map);
      expect(char.alternateGreetings, isEmpty);
    });

    test('copyWith updates individual fields', () {
      final original = CharacterProfile(
        name: 'Old',
        personality: 'Old',
        firstMessage: 'Old',
      );
      final updated = original.copyWith(
        name: 'New',
        personality: 'New personality',
        isFavorite: true,
      );

      expect(updated.name, equals('New'));
      expect(updated.personality, equals('New personality'));
      expect(updated.isFavorite, isTrue);
      expect(updated.firstMessage, equals(original.firstMessage));
      expect(updated.id, equals(original.id));
    });

    test('default alternateGreetings is empty list', () {
      final char = CharacterProfile(
        name: 'Test',
        personality: 'Test',
        firstMessage: 'Test',
      );
      expect(char.alternateGreetings, isEmpty);
      expect(char.alternateGreetings is List<String>, isTrue);
    });

    test('fromMap uses fallback id when missing', () {
      final map = <String, dynamic>{
        'name': 'Test',
        'personality': 'Test',
        'first_message': 'Test',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      final char = CharacterProfile.fromMap(map);
      expect(char.id, isNotNull);
      expect(char.id.isNotEmpty, isTrue);
    });

    test('fromMap uses fallback name when missing', () {
      final map = <String, dynamic>{
        'id': 'c1',
        'personality': 'Test',
        'first_message': 'Test',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      final char = CharacterProfile.fromMap(map);
      expect(char.name, equals('Unknown'));
    });

    test('fromMap parses createdAt and updatedAt', () {
      final now = DateTime.now();
      final map = <String, dynamic>{
        'id': 'c1',
        'name': 'Test',
        'personality': 'Test',
        'first_message': 'Test',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      final char = CharacterProfile.fromMap(map);
      expect(char.createdAt.isAtSameMomentAs(now), isTrue);
      expect(char.updatedAt.isAtSameMomentAs(now), isTrue);
    });

    test('fromMap handles invalid date strings', () {
      final map = <String, dynamic>{
        'id': 'c1',
        'name': 'Test',
        'personality': 'Test',
        'first_message': 'Test',
        'created_at': 'not-a-date',
        'updated_at': 'also-not-a-date',
      };
      final char = CharacterProfile.fromMap(map);
      expect(char.createdAt, isNotNull);
      expect(char.updatedAt, isNotNull);
    });
  });

  group('PersonaTemplate model roundtrip', () {
    test('toMap/fromMap preserves all fields', () {
      final original = PersonaTemplate(
        id: 'tpl-1',
        name: 'Detective',
        description: 'A sharp detective persona',
      );

      final map = original.toMap();
      final restored = PersonaTemplate.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.description, equals(original.description));
      expect(restored.createdAt, isNotNull);
      expect(restored.updatedAt, isNotNull);
    });

    test('copyWith updates fields', () {
      final original = PersonaTemplate(
        name: 'Old',
        description: 'Old desc',
      );
      final updated = original.copyWith(name: 'New', description: 'New desc');

      expect(updated.name, equals('New'));
      expect(updated.description, equals('New desc'));
      expect(updated.id, equals(original.id));
    });

    test('fromMap uses fallback values', () {
      final map = <String, dynamic>{
        'id': 'tpl-1',
        'name': 'Test',
        'persona_text': 'Test description',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      final tpl = PersonaTemplate.fromMap(map);
      expect(tpl.id, equals('tpl-1'));
    });

    test('toJson/fromString roundtrip', () {
      final original = PersonaTemplate(
        name: 'Detective',
        description: 'A sharp detective persona',
      );
      final json = original.toJson();
      final restored = PersonaTemplate.fromJson(json);

      expect(restored.name, equals(original.name));
      expect(restored.description, equals(original.description));
    });

    test('toString includes name and description length', () {
      final tpl = PersonaTemplate(
        name: 'Detective',
        description: 'A short description',
      );
      final str = tpl.toString();
      expect(str, contains('Detective'));
      expect(str, contains('19 chars'));
    });
  });

  group('ServerConfig model roundtrip', () {
    test('defaults match app constants', () {
      const config = ServerConfig();
      expect(config.name, equals(defaultServerName));
      expect(config.systemPrompt, equals(defaultSystemPrompt));
      expect(config.confirmDeleteMessage, isTrue);
      expect(config.reasoning, isFalse);
      expect(config.healthStatus, equals(ServerHealthStatus.offline));
      expect(config.latencyMs, equals(-1));
    });

    test('toMap/fromMap preserves all fields', () {
      final config = ServerConfig(
        name: 'My Server',
        selectedModel: 'llama-3.2',
        systemPrompt: 'Custom prompt',
        confirmDeleteMessage: false,
        reasoning: true,
      );

      final map = config.toMap();
      final restored = ServerConfig.fromMap(map);

      expect(restored.name, equals(config.name));
      expect(restored.selectedModel, equals(config.selectedModel));
      expect(restored.systemPrompt, equals(config.systemPrompt));
      expect(restored.confirmDeleteMessage, equals(config.confirmDeleteMessage));
      expect(restored.reasoning, equals(config.reasoning));
    });

    test('toMap serializes defaultParams', () {
      final config = ServerConfig(
        defaultParams: const GenerationParams(
          temperature: 0.8,
          maxTokens: 2048,
        ),
      );

      final map = config.toMap();
      final paramsJson = map['default_params'] as String;
      final decoded = jsonDecode(paramsJson) as Map<String, dynamic>;
      expect(decoded['temperature'], equals(0.8));
      expect(decoded['max_tokens'], equals(2048));
    });

    test('fromMap parses serialized defaultParams', () {
      final map = <String, dynamic>{
        'name': 'Test',
        'default_params': '{"temperature":0.8,"max_tokens":2048}',
      };
      final config = ServerConfig.fromMap(map);
      expect(config.defaultParams.temperature, equals(0.8));
      expect(config.defaultParams.maxTokens, equals(2048));
    });

    test('fromMap handles missing default_params', () {
      final map = <String, dynamic>{
        'name': 'Test',
      };
      final config = ServerConfig.fromMap(map);
      expect(config.defaultParams, const TypeMatcher<GenerationParams>());
      expect(config.defaultParams.temperature, equals(0.7));
    });

    test('copyWith preserves legacy fields', () {
      final config = ServerConfig(
        legacyBaseUrl: 'http://localhost:8080',
        legacyApiKey: 'secret',
        legacyProtocol: ApiProtocol.llamaNative,
      );
      final copied = config.copyWith(name: 'New Name');

      expect(copied.baseUrl, equals('http://localhost:8080'));
      expect(copied.apiKey, equals('secret'));
      expect(copied.protocol, equals(ApiProtocol.llamaNative));
      expect(copied.name, equals('New Name'));
    });

    test('copyWith updates reasoning flag', () {
      final config = const ServerConfig();
      final updated = config.copyWith(reasoning: true);
      expect(updated.reasoning, isTrue);
    });

    test('copyWith updates confirmDeleteMessage flag', () {
      final config = const ServerConfig();
      final updated = config.copyWith(confirmDeleteMessage: false);
      expect(updated.confirmDeleteMessage, isFalse);
    });

    test('fromMap parses protocol', () {
      final map = <String, dynamic>{
        'name': 'Test',
        'protocol': 'llamaNative',
      };
      final config = ServerConfig.fromMap(map);
      expect(config.protocol, equals(ApiProtocol.llamaNative));
    });

    test('fromMap falls back to openAi for unknown protocol', () {
      final map = <String, dynamic>{
        'name': 'Test',
        'protocol': 'unknown',
      };
      final config = ServerConfig.fromMap(map);
      expect(config.protocol, equals(ApiProtocol.openAi));
    });
  });

  group('ServerProfile model roundtrip', () {
    test('toMap/fromMap preserves all fields', () {
      final original = ServerProfile(
        id: 'profile-1',
        name: 'My Server',
        baseUrl: 'http://localhost:8080',
        apiKey: 'secret-key',
        protocol: ApiProtocol.llamaNative,
      );

      final map = original.toMap();
      final restored = ServerProfile.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.baseUrl, equals(original.baseUrl));
      expect(restored.apiKey, equals(original.apiKey));
      expect(restored.protocol, equals(original.protocol));
    });

    test('copyWith updates individual fields', () {
      final original = ServerProfile(
        name: 'Old',
        baseUrl: 'http://old',
        protocol: ApiProtocol.openAi,
      );
      final updated = original.copyWith(
        name: 'New',
        baseUrl: 'http://new',
      );

      expect(updated.name, equals('New'));
      expect(updated.baseUrl, equals('http://new'));
      expect(updated.protocol, equals(ApiProtocol.openAi));
      expect(updated.id, equals(original.id));
    });

    test('fromMap uses fallback values', () {
      final map = <String, dynamic>{
        'id': 'tpl-1',
        'name': 'Test',
        'persona_text': 'Test description',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      final tpl = PersonaTemplate.fromMap(map);
      expect(tpl.id, equals('tpl-1'));
    });

    test('fromMap handles missing protocol as openAi', () {
      final map = <String, dynamic>{
        'id': 'profile-1',
        'name': 'Test',
      };
      final profile = ServerProfile.fromMap(map);
      expect(profile.protocol, equals(ApiProtocol.openAi));
    });
  });
}
