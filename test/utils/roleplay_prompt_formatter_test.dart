import 'package:clan_ai/core/utils/roleplay_prompt_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoleplayPromptFormatter buildSystemPrompt', () {
    test('includes personality in prompt', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Brave and cunning warrior',
        retrievedMemories: [],
      );

      expect(prompt, contains('Brave and cunning warrior'));
      expect(prompt, contains('Aria'));
    });

    test('includes setting when provided', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        setting: 'A dark fantasy realm',
        retrievedMemories: [],
      );

      expect(prompt, contains('A dark fantasy realm'));
    });

    test('includes userPersona when provided', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        userPersona: 'A wandering knight',
        retrievedMemories: [],
      );

      expect(prompt, contains('A wandering knight'));
      expect(prompt, contains('Your roleplay partner\'s persona'));
    });

    test('includes identity guard text', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        retrievedMemories: [],
      );

      expect(prompt, contains('roleplaying as "Aria"'));
      expect(prompt, contains('Never speak, think, act, or write dialogue for the user'));
      expect(prompt, contains('Never break character'));
    });

    test('appends postHistoryInstructions when provided', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        retrievedMemories: [],
        postHistoryInstructions: 'Always respond in first person.',
      );

      expect(prompt, contains('Always respond in first person.'));
    });

    test('does not append postHistoryInstructions when null', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        retrievedMemories: [],
        postHistoryInstructions: null,
      );

      expect(prompt, isNot(contains('first person')));
    });

    test('uses custom characterSystemPrompt when provided', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        retrievedMemories: [],
        characterSystemPrompt: 'You are a medieval merchant.',
      );

      expect(prompt, contains('You are a medieval merchant'));
      expect(prompt, isNot(contains('Brave')));
    });

    test('{{original}} prefix inserts standard prompt before custom', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        retrievedMemories: [],
        characterSystemPrompt: '{{original}}\n\nSpeak in archaic English.',
      );

      expect(prompt, contains('roleplaying as "Aria"'));
      expect(prompt, contains('Speak in archaic English.'));
    });

    test('truncates personality at 2000 chars', () {
      final longPersonality = 'Brave. ' * 1000;
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: longPersonality,
        retrievedMemories: [],
      );

      expect(prompt, contains('[truncated]'));
      expect(prompt.length, lessThanOrEqualTo(2500));
    });

    test('truncates setting at 1000 chars', () {
      final longSetting = 'A world. ' * 120;
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        setting: longSetting,
        retrievedMemories: [],
      );

      expect(prompt, contains('[truncated]'));
    });

    test('truncates userPersona at 1000 chars', () {
      final longPersona = 'A knight. ' * 120;
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        userPersona: longPersona,
        retrievedMemories: [],
      );

      expect(prompt, contains('[truncated]'));
    });

    test('limits retrieved memories to top 3', () {
      final memories = List.generate(10, (i) => 'Memory $i content here.');
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        retrievedMemories: memories,
      );

      // Should contain only first 3 memories
      var count = 0;
      for (int i = 0; i < 3; i++) {
        if (prompt.contains('Memory $i content here.')) count++;
      }
      expect(count, equals(3));

      // Memory 4+ should not appear
      expect(prompt, isNot(contains('Memory 4 content here.')));
    });

    test('truncates each memory at 1000 chars', () {
      final longMemory = 'Memory content. ' * 100;
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        retrievedMemories: [longMemory],
      );

      expect(prompt, contains('[truncated]'));
    });

    test('empty personality is omitted', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: '',
        retrievedMemories: [],
      );

      expect(prompt, isNot(contains('Empty')));
    });

    test('empty setting is omitted', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        setting: '',
        retrievedMemories: [],
      );

      expect(prompt, isNot(contains('Setting')));
    });

    test('empty userPersona is omitted', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        userPersona: '',
        retrievedMemories: [],
      );

      expect(prompt, isNot(contains('Your roleplay partner')));
    });

    test('no memories section when empty list', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        retrievedMemories: [],
      );

      expect(prompt, isNot(contains('Character Memories')));
    });

    test('whitespace-only setting is omitted', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        setting: '   ',
        retrievedMemories: [],
      );

      expect(prompt, isNot(contains('Setting')));
    });

    test('whitespace-only userPersona is omitted', () {
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        userPersona: '   ',
        retrievedMemories: [],
      );

      expect(prompt, isNot(contains('Your roleplay partner')));
    });
  });

  group('RoleplayPromptFormatter buildOpenAiSystemMessage', () {
    test('returns correct structure with role and content', () {
      final result = RoleplayPromptFormatter.buildOpenAiSystemMessage(
        characterName: 'Aria',
        personality: 'Warrior',
        retrievedMemories: [],
      );

      expect(result['role'], equals('system'));
      expect(result['content'], contains('Aria'));
      expect(result['content'], contains('Warrior'));
    });

    test('includes custom system prompt in content', () {
      final result = RoleplayPromptFormatter.buildOpenAiSystemMessage(
        characterName: 'Aria',
        personality: 'Warrior',
        characterSystemPrompt: 'Custom prompt here.',
        retrievedMemories: [],
      );

      expect(result['content'], contains('Custom prompt here.'));
    });
  });

  group('RoleplayPromptFormatter buildAssistantPrompt', () {
    test('formats assistant header correctly', () {
      final result = RoleplayPromptFormatter.buildAssistantPrompt(
        characterName: 'Aria',
      );

      expect(result, equals('### Assistant:\n[Aria]: '));
    });

    test('includes userPersona in header', () {
      final result = RoleplayPromptFormatter.buildAssistantPrompt(
        characterName: 'Aria',
        userPersona: 'A knight',
      );

      expect(result, contains('Aria'));
    });
  });
}
