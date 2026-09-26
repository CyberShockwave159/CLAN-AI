import 'dart:typed_data';
import 'package:clan_ai/core/constants/aprox_capabilities.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/ui/features/roleplay/services/scene_image_generator.dart';
import 'package:clan_ai/data/datasources/llama_api_service.dart';

/// One-shot model calls that support character image consistency.
///
/// Separate from the streaming scene-image flow because these are auxiliary:
/// they produce a value for a form field, not a message. Each is a single
/// non-streaming completion whose response is discarded after parsing, so
/// nothing leaks into the conversation or into memory.
class CharacterImageAssist {
  CharacterImageAssist._();

  /// The token budget is governed by `LlamaApiService.completeOnce`, which caps
  /// every auxiliary call — each of these produces a few dozen words at most.

  /// Minimum card length before an appearance draft is worth attempting.
  ///
  /// Below this the "card" is a name and a one-liner, and the model would
  /// invent physical traits the user never specified — worse than no sheet.
  static const int minimumCardLengthForDraft = 200;

  /// Whether a character card is rich enough to draft an appearance sheet from.
  static bool canDraftAppearance(CharacterProfile character) {
    return !character.hasAppearance &&
        character.personality.trim().length >= minimumCardLengthForDraft;
  }

  /// Drafts a canonical appearance description from a character's card.
  ///
  /// Returns null when the card is too thin, the model reports no physical
  /// details (the sentinel `NONE`), or the call fails. Callers must review the
  /// result before storing it — a bad extraction is invisible until the images
  /// come out wrong.
  static Future<String?> draftAppearance({
    required ChatRepository chatRepository,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    required CharacterProfile character,
  }) async {
    if (!canDraftAppearance(character)) return null;
    try {
      final response = await chatRepository.completeOnce(
        serverConfig: serverConfig,
        connection: connection,
        systemPrompt: SceneImagePrompts.appearanceWriterSystemPrompt,
        messages: [
          {
            'role': 'user',
            'content':
                '${SceneImagePrompts.appearanceWriterInstruction}${character.personality.trim()}',
          },
        ],
      );
      final draft = response.trim();
      if (draft.isEmpty || draft.toUpperCase() == 'NONE') return null;
      // The model is told to answer with prose only; strip a stray label or
      // bullet formatting so the sheet reads cleanly inside a prompt.
      return draft
          .replaceFirst(RegExp(r'^(appearance|physical appearance)\s*:\s*', caseSensitive: false), '')
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^\s*[-*•]\s*'), '').trim())
          .where((l) => l.isNotEmpty)
          .join('\n')
          .trim();
    } catch (_) {
      return null;
    }
  }

  /// Classifies an avatar's visual style.
  ///
  /// Requires a vision-capable upstream model; returns null (rather than
  /// guessing) when the call fails or the reply isn't one of the three known
  /// styles.
  static Future<VisualTheme?> detectVisualStyle({
    required ChatRepository chatRepository,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    required Uint8List avatarBytes,
  }) async {
    if (avatarBytes.isEmpty) return null;
    try {
      final response = await chatRepository.completeOnce(
        serverConfig: serverConfig,
        connection: connection,
        systemPrompt: SceneImagePrompts.styleDetectorSystemPrompt,
        messages: [
          {
            'role': 'user',
            'content': LlamaApiService.buildImageContentParts(
              text: SceneImagePrompts.styleDetectorInstruction,
              imageBytes: avatarBytes,
            ),
          },
        ],
      );
      return _parseStyle(response);
    } catch (_) {
      return null;
    }
  }

  /// Parses a one-word style reply, tolerating a chatty model.
  static VisualTheme? _parseStyle(String raw) {
    final lower = raw.toLowerCase();
    // Longest-match first: "semi-realistic" contains "realistic", and
    // "photo-realistic" must not be read as "semi-realistic".
    if (lower.contains('semi')) return VisualTheme.semiRealistic;
    if (lower.contains('anime')) return VisualTheme.anime;
    if (lower.contains('photo') || lower.contains('realistic')) {
      return VisualTheme.photoRealistic;
    }
    return null;
  }
}
