import 'package:clan_ai/core/utils/silly_tavern_card_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ParsedCharacterCard.fromJson', () {
    test('parses valid chara_card_v2 spec_version 2.0', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': 'A brave warrior',
          'personality': 'Cunning and strong',
          'first_mes': 'Hello there, traveler!',
          'scenario': 'A dark forest',
          'user_persona': 'A wandering knight',
          'avatar': 'http://example.com/avatar.png',
          'system_prompt': 'You are a medieval character.',
          'post_history_instructions': 'Keep responses short.',
          'alternate_greetings': ['Hi!', 'Greetings!'],
        },
      };

      final card = ParsedCharacterCard.fromJson(json);

      expect(card.isValid, isTrue);
      expect(card.name, equals('Aria'));
      expect(card.personality, contains('A brave warrior'));
      expect(card.firstMessage, equals('Hello there, traveler!'));
      expect(card.setting, equals('A dark forest'));
      expect(card.userPersona, equals('A wandering knight'));
      expect(card.avatarUrl, equals('http://example.com/avatar.png'));
      expect(card.systemPrompt, equals('You are a medieval character.'));
      expect(card.postHistoryInstructions, equals('Keep responses short.'));
      expect(card.alternateGreetings, hasLength(2));
    });

    test('rejects invalid spec', () {
      final json = {
        'spec': 'chara_card_v1',
        'spec_version': '1.0',
        'data': {
          'name': 'Old Card',
          'description': 'Old description',
          'first_mes': 'Hello',
        },
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.isValid, isFalse);
      expect(card.name, equals(''));
    });

    test('rejects missing data field', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.isValid, isFalse);
    });

    test('replaces {{char}} with character name in personality', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': '{{char}} is brave.',
          'first_mes': 'Hi {{user}}',
          'personality': '{{char}} fights well.',
        },
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.personality, contains('Aria'));
      expect(card.firstMessage, contains('User'));
    });

    test('replaces {{user}} with user persona name', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': '{{user}} is brave.',
          'first_mes': 'Hi {{user}}',
          'user_persona': 'Detective\nSharp mind',
        },
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.firstMessage, contains('Detective'));
    });

    test('falls back to "User" when userPersona is empty', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': '{{user}} is here.',
          'first_mes': 'Hi {{user}}',
          'user_persona': '',
        },
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.firstMessage, contains('User'));
    });

    test('truncates personality at 4000 chars', () {
      final longDescription = 'A ' * 5000;
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': longDescription,
          'first_mes': 'Hello',
        },
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.personality.length, lessThanOrEqualTo(4000));
    });

    test('appends mes_example to personality', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': 'A warrior.',
          'first_mes': 'Hello',
          'mes_example': '{{char}}: Hello there.\n{{user}}: Hi!',
        },
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.personality, contains('[Example Dialogue]'));
      expect(card.personality, contains('Hello there'));
    });

    test('handles null optional fields gracefully', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': 'A warrior.',
          'first_mes': 'Hello',
          'scenario': null,
          'user_persona': null,
          'avatar': null,
          'system_prompt': null,
          'post_history_instructions': null,
        },
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.setting, isNull);
      expect(card.userPersona, isNull);
      expect(card.avatarUrl, isNull);
      expect(card.systemPrompt, isNull);
      expect(card.postHistoryInstructions, isNull);
      expect(card.alternateGreetings, isEmpty);
    });

    test('cleans avatar URL (only http/https)', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': 'A warrior.',
          'first_mes': 'Hello',
          'avatar': 'local_file.png',
        },
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.avatarUrl, isNull);
    });

    test('cleans avatar URL (http prefix)', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': 'A warrior.',
          'first_mes': 'Hello',
          'avatar': '  http://example.com/img.png  ',
        },
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.avatarUrl, equals('http://example.com/img.png'));
    });

    test('valid requires non-empty name, personality, and firstMessage', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': '',
          'description': 'A warrior.',
          'first_mes': 'Hello',
        },
      };

      expect(ParsedCharacterCard.fromJson(json).isValid, isFalse);

      final json2 = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': '',
          'first_mes': 'Hello',
        },
      };

      expect(ParsedCharacterCard.fromJson(json2).isValid, isFalse);

      final json3 = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': 'A warrior.',
          'first_mes': '',
        },
      };

      expect(ParsedCharacterCard.fromJson(json3).isValid, isFalse);
    });

    test('filters empty alternate greetings', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': 'A warrior.',
          'first_mes': 'Hello',
          'alternate_greetings': ['Hi!', '', '  ', 'Greetings!'],
        },
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.alternateGreetings, hasLength(2));
      expect(card.alternateGreetings, contains('Hi!'));
      expect(card.alternateGreetings, contains('Greetings!'));
    });

    test('trims whitespace from fields', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': '  Aria  ',
          'description': '  A warrior  ',
          'first_mes': '  Hello  ',
          'scenario': '  A forest  ',
          'user_persona': '  A knight  ',
        },
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.name, equals('Aria'));
      expect(card.firstMessage, equals('Hello'));
      expect(card.setting, equals('A forest'));
      expect(card.userPersona, equals('A knight'));
    });

    test('{{char}} replacement in setting', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': 'A warrior.',
          'first_mes': 'Hello',
          'scenario': '{{char}} stands in {{user}}\'s castle.',
        },
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.setting, contains('Aria'));
      expect(card.setting, contains('User\'s castle'));
    });

    test('{{char}}/{{user}} replacement in alternate greetings', () {
      final json = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': 'Aria',
          'description': 'A warrior.',
          'first_mes': 'Hello',
          'alternate_greetings': ['Hello {{user}}', '{{char}} greets you'],
        },
      };

      final card = ParsedCharacterCard.fromJson(json);
      expect(card.alternateGreetings, contains('Hello User'));
      expect(card.alternateGreetings, contains('Aria greets you'));
    });
  });
}
