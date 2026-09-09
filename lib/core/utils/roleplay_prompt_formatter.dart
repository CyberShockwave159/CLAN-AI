/// Compiles the roleplay system prompt from character details, user persona,
/// and retrieved memories into a structured payload for llama.cpp.
///
/// Produces both the native `### System:` format and the OpenAI chat format.
class RoleplayPromptFormatter {

  /// Build the system prompt string for llama.cpp native format.
  static String buildSystemPrompt({
    required String characterName,
    required String personality,
    String? setting,
    String? userPersona,
    String? personaName,
    required List<String> retrievedMemories,
    String? characterSystemPrompt,
    String? postHistoryInstructions,
  }) {
    final parts = <String>[];

    // Character system prompt override (replaces entire prompt if present)
    if (characterSystemPrompt != null && characterSystemPrompt.isNotEmpty) {
      // Support {{original}} prefix - insert standard prompt before custom prompt
      if (characterSystemPrompt.startsWith('{{original}}')) {
        final standardPrompt = _buildStandardPrompt(
          characterName: characterName,
          personality: personality,
          setting: setting,
          userPersona: userPersona,
          personaName: personaName,
          memories: retrievedMemories,
        );
        final customPrompt = characterSystemPrompt.substring('{{original}}'.length).trim();
        parts.add('$standardPrompt\n\n$customPrompt');
      } else {
        parts.add(characterSystemPrompt);
      }

      // Append post history instructions if present
      if (postHistoryInstructions != null && postHistoryInstructions.isNotEmpty) {
        parts.add('\n\n$postHistoryInstructions');
      }

      return parts.join('\n');
    }

    // Standard prompt building
    parts.add(_buildStandardPrompt(
      characterName: characterName,
      personality: personality,
      setting: setting,
      userPersona: userPersona,
      personaName: personaName,
      memories: retrievedMemories,
    ));

    // Append post history instructions if present
    if (postHistoryInstructions != null && postHistoryInstructions.isNotEmpty) {
      parts.add('\n\n$postHistoryInstructions');
    }

    return parts.join('\n');
  }

  static String _buildStandardPrompt({
    required String characterName,
    required String personality,
    String? setting,
    String? userPersona,
    String? personaName,
    required List<String> memories,
  }) {
    final parts = <String>[];

    // Character personality
    if (personality.isNotEmpty) {
      parts.add(personality.trim());
    }

    // Setting / world description
    if (setting != null && setting.trim().isNotEmpty) {
      parts.add('\n\nSetting: $setting');
    }

    // Character identity
    parts.add('\n\nYou are roleplaying as "$characterName". Respond strictly in character. '
        'Never break character or acknowledge that you are an AI. '
        'Never speak, think, act, or write dialogue for the user — only write for your own character.');

    // User persona and name
    if (personaName != null && personaName.isNotEmpty) {
      parts.add('\n\nYour roleplay partner\'s name: $personaName');
    }
    if (userPersona != null && userPersona.trim().isNotEmpty) {
      parts.add('\n\nYour roleplay partner\'s persona: $userPersona');
    }

    // Retrieved memories
    if (memories.isNotEmpty) {
      parts.add('\n\n[Character Memories — relevant facts from prior conversation]:');
      for (final memory in memories) {
        parts.add('  - $memory');
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
    String? personaName,
    required List<String> retrievedMemories,
    String? characterSystemPrompt,
    String? postHistoryInstructions,
  }) {
    return {
      'role': 'system',
      'content': buildSystemPrompt(
        characterName: characterName,
        personality: personality,
        setting: setting,
        userPersona: userPersona,
        personaName: personaName,
        retrievedMemories: retrievedMemories,
        characterSystemPrompt: characterSystemPrompt,
        postHistoryInstructions: postHistoryInstructions,
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
