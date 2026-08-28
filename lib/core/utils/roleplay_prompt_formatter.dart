/// Compiles the roleplay system prompt from character details, user persona,
/// and retrieved memories into a structured payload for llama.cpp.
///
/// Produces both the native `### System:` format and the OpenAI chat format.
class RoleplayPromptFormatter {
  static const _maxPersonalityLength = 2000;
  static const _maxSettingLength = 1000;
  static const _maxUserPersonaLength = 1000;
  static const _maxMemoryLength = 1000;
  static const _maxMemoriesInPrompt = 3;

  /// Build the system prompt string for llama.cpp native format.
  static String buildSystemPrompt({
    required String characterName,
    required String personality,
    String? setting,
    String? userPersona,
    required List<String> retrievedMemories,
  }) {
    final parts = <String>[];

    // Character personality
    if (personality.isNotEmpty) {
      if (personality.length > _maxPersonalityLength) {
        parts.add('${personality.substring(0, _maxPersonalityLength)}... [truncated]');
      } else {
        parts.add(personality.trim());
      }
    }

    // Setting / world description
    if (setting != null && setting.trim().isNotEmpty) {
      if (setting.length > _maxSettingLength) {
        parts.add('\n\nSetting: ${setting.substring(0, _maxSettingLength)}... [truncated]');
      } else {
        parts.add('\n\nSetting: $setting');
      }
    }

    // Character identity
    parts.add('\n\nYou are roleplaying as "$characterName". Respond strictly in character. '
        'Never break character or acknowledge that you are an AI. '
        'Never speak, think, act, or write dialogue for the user — only write for your own character.');

    // User persona
    if (userPersona != null && userPersona.trim().isNotEmpty) {
      if (userPersona.length > _maxUserPersonaLength) {
        parts.add('\n\nYour roleplay partner\'s persona: ${userPersona.substring(0, _maxUserPersonaLength)}... [truncated]');
      } else {
        parts.add('\n\nYour roleplay partner\'s persona: $userPersona');
      }
    }

    // Retrieved memories (limited)
    if (retrievedMemories.isNotEmpty) {
      parts.add('\n\n[Character Memories — relevant facts from prior conversation]:');
      final limitedMemories = retrievedMemories.take(_maxMemoriesInPrompt);
      for (final memory in limitedMemories) {
        if (memory.length > _maxMemoryLength) {
          parts.add('  - ${memory.substring(0, _maxMemoryLength)}... [truncated]');
        } else {
          parts.add('  - $memory');
        }
      }
    }

    return parts.join('\n');
  }

  /// Build the system message for OpenAI-compatible format.
  static Map<String, String> buildOpenAiSystemMessage({
    required String characterName,
    required String personality,
    String? setting,
    String? userPersona,
    required List<String> retrievedMemories,
  }) {
    return {
      'role': 'system',
      'content': buildSystemPrompt(
        characterName: characterName,
        personality: personality,
        setting: setting,
        userPersona: userPersona,
        retrievedMemories: retrievedMemories,
      ),
    };
  }

  /// Format the assistant's response header for the native prompt.
  static String buildAssistantPrompt({
    required String characterName,
    String? userPersona,
  }) {
    return '### Assistant:\n[$characterName]: ';
  }
}
