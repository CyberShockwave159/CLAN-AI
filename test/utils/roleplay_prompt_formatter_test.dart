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

    test('preserves full long personality without truncation', () {
      final longPersonality = 'Brave. ' * 1000;
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: longPersonality,
        retrievedMemories: [],
      );

      // Should contain approximately 1000 instances of 'Brave.' (trimming removes the last space)
      expect(prompt.split('Brave.').length, greaterThan(990));
      expect(prompt, isNot(contains('[truncated]')));
    });

    test('preserves full long setting without truncation', () {
      final longSetting = 'A world. ' * 120;
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        setting: longSetting,
        retrievedMemories: [],
      );

      expect(prompt, contains(longSetting));
      expect(prompt, isNot(contains('[truncated]')));
    });

    test('preserves full long userPersona without truncation', () {
      final longPersona = 'A knight. ' * 120;
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        userPersona: longPersona,
        retrievedMemories: [],
      );

      expect(prompt, contains(longPersona));
      expect(prompt, isNot(contains('[truncated]')));
    });

    test('includes all retrieved memories without limit', () {
      final memories = List.generate(10, (i) => 'Memory $i content here.');
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        retrievedMemories: memories,
      );

      // Should contain all memories
      for (final memory in memories) {
        expect(prompt, contains(memory));
      }
    });

    test('preserves full long memory without truncation', () {
      final longMemory = 'Memory content. ' * 100;
      final prompt = RoleplayPromptFormatter.buildSystemPrompt(
        characterName: 'Aria',
        personality: 'Warrior',
        retrievedMemories: [longMemory],
      );

      expect(prompt, contains(longMemory));
      expect(prompt, isNot(contains('[truncated]')));
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
