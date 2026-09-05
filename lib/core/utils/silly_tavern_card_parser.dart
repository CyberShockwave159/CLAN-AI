/// Parses SillyTavern chara_card_v2 JSON files into a structured DTO.
///
/// Only supports spec_version 2.0. Rejects cards that don't match the expected
/// structure or have missing required fields.
class ParsedCharacterCard {
  final String name;
  final String personality;
  final String firstMessage;
  final String? setting;
  final String? userPersona;
  final String? avatarUrl;
  final String? systemPrompt;
  final String? postHistoryInstructions;
  final List<String> alternateGreetings;
  final bool isValid;

  const ParsedCharacterCard({
    required this.name,
    required this.personality,
    required this.firstMessage,
    this.setting,
    this.userPersona,
    this.avatarUrl,
    this.systemPrompt,
    this.postHistoryInstructions,
    this.alternateGreetings = const [],
    this.isValid = true,
  });

  static ParsedCharacterCard fromJson(Map<String, dynamic> json) {
    final spec = json['spec'] as String?;
    final specVersion = json['spec_version'] as String?;

    // Only support chara_card_v2 with version 2.0
    if (spec != 'chara_card_v2' || specVersion != '2.0') {
      return const ParsedCharacterCard(
        name: '',
        personality: '',
        firstMessage: '',
        isValid: false,
      );
    }

    final data = json['data'];
    if (data == null || data is! Map<String, dynamic>) {
      return const ParsedCharacterCard(
        name: '',
        personality: '',
        firstMessage: '',
        isValid: false,
      );
    }

    final name = (data['name'] as String?)?.trim() ?? '';
    final description = (data['description'] as String?) ?? '';
    final personalityField = (data['personality'] as String?) ?? '';
    final firstMes = (data['first_mes'] as String?)?.trim() ?? '';
    final scenario = (data['scenario'] as String?)?.trim();
    final userPersona = (data['user_persona'] as String?)?.trim();
    final avatar = (data['avatar'] as String?)?.trim();
    final mesExample = (data['mes_example'] as String?) ?? '';

    // System prompt with {{original}} prefix support
    final rawSystemPrompt = (data['system_prompt'] as String?)?.trim();
    String? systemPrompt;
    if (rawSystemPrompt != null && rawSystemPrompt.isNotEmpty) {
      systemPrompt = rawSystemPrompt;
    }

    // Post history instructions
    final rawPostHistory = (data['post_history_instructions'] as String?)?.trim();
    String? postHistoryInstructions;
    if (rawPostHistory != null && rawPostHistory.isNotEmpty) {
      postHistoryInstructions = rawPostHistory;
    }

    // Alternate greetings
    List<String> alternateGreetings = [];
    final altGreetingsRaw = data['alternate_greetings'] as List<dynamic>?;
    if (altGreetingsRaw != null) {
      alternateGreetings = altGreetingsRaw
          .map((e) => (e as String).trim())
          .where((g) => g.isNotEmpty)
          .toList();
    }

    // Replace {{char}} with actual character name, {{user}} with user persona
    final userName = userPersona?.trim().isNotEmpty == true ? userPersona!.trim().split('\n').first.trim() : 'User';
    String combinedPersonality = description.trim();
    if (personalityField.trim().isNotEmpty) {
      if (combinedPersonality.isNotEmpty) {
        combinedPersonality = '$combinedPersonality\n\n---\n\n${personalityField.trim()}';
      } else {
        combinedPersonality = personalityField.trim();
      }
    }

    // Append mes_example if non-empty
    if (mesExample.trim().isNotEmpty) {
      if (combinedPersonality.isNotEmpty) {
        combinedPersonality = '$combinedPersonality\n\n---\n\n[Example Dialogue]\n${mesExample.trim()}';
      } else {
        combinedPersonality = mesExample.trim();
      }
    }

    // Replace {{char}} with character name, {{user}} with user persona name
    combinedPersonality = combinedPersonality.replaceAll('{{char}}', name);
    combinedPersonality = combinedPersonality.replaceAll('{{user}}', userName);

    // Truncate personality if too long
    const maxPersonalityLength = 4000;
    if (combinedPersonality.length > maxPersonalityLength) {
      combinedPersonality = combinedPersonality.substring(0, maxPersonalityLength);
    }

    // Clean up avatar URL
    String? cleanAvatarUrl;
    if (avatar != null && avatar.isNotEmpty && avatar.startsWith('http')) {
      cleanAvatarUrl = avatar;
    }

    // Clean up optional fields - replace {{char}}/{{user}}
    String? cleanSetting;
    if (scenario != null && scenario.isNotEmpty) {
      cleanSetting = scenario.replaceAll('{{char}}', name).replaceAll('{{user}}', userName);
    }

    String? cleanUserPersona;
    if (userPersona != null && userPersona.isNotEmpty) {
      cleanUserPersona = userPersona.replaceAll('{{char}}', name).replaceAll('{{user}}', userName);
    }

    // Replace {{char}}/{{user}} in first message too
    final firstMesClean = firstMes.replaceAll('{{char}}', name).replaceAll('{{user}}', userName);

    // Clean up alternate greetings
    final cleanAltGreetings = alternateGreetings
        .map((g) => g.replaceAll('{{char}}', name).replaceAll('{{user}}', userName))
        .toList();

    final isValid = name.isNotEmpty &&
        combinedPersonality.isNotEmpty &&
        firstMesClean.isNotEmpty;

    return ParsedCharacterCard(
      name: name,
      personality: combinedPersonality,
      firstMessage: firstMesClean,
      setting: cleanSetting,
      userPersona: cleanUserPersona,
      avatarUrl: cleanAvatarUrl,
      systemPrompt: systemPrompt != null && systemPrompt.isNotEmpty ? systemPrompt : null,
      postHistoryInstructions: postHistoryInstructions != null && postHistoryInstructions.isNotEmpty ? postHistoryInstructions : null,
      alternateGreetings: cleanAltGreetings,
      isValid: isValid,
    );
  }
}
