import 'package:clan_ai/core/constants/aprox_capabilities.dart';
import 'package:clan_ai/data/models/chat_message.dart';

/// Outcome of a scene-image generation attempt.
enum SceneImageOutcome {
  /// An image was generated and attached to the new variant.
  generated,

  /// The server doesn't advertise image generation.
  unsupported,

  /// A generation was already in flight.
  busy,

  /// The request completed but produced no image. The variant was reverted.
  noImage,

  /// The request failed. The variant was reverted.
  failed,
}

/// Result of a scene-image generation, for the caller to report to the user.
class SceneImageResult {
  final SceneImageOutcome outcome;

  /// Populated for [SceneImageOutcome.failed] / [noImage], suitable for a
  /// snackbar.
  final String? message;

  const SceneImageResult(this.outcome, {this.message});

  bool get isSuccess => outcome == SceneImageOutcome.generated;
}

/// Assembles the context for a scene-image request.
///
/// The flow is two steps because A-PROX rewrites the prompt anyway. `/image`
/// arms the `image_generate` tool behind a prompt *enhancer*
/// (`prompts/i-iprompt.txt`) that treats every request as an image-editing task
/// and emits its own `rewritten_prompt`. Writing a scene description first and
/// handing that over as the tool's request produces a far better picture than
/// asking the enhancer to infer the scene from a bare command — and it lets the
/// canonical appearance sheet and the theme be present in the text the enhancer
/// elaborates on.
class SceneImagePrompts {
  SceneImagePrompts._();

  /// System prompt for step 1: turning the last few exchanges into an
  /// image-generation prompt.
  ///
  /// Deliberately minimal and roleplay-free. The character's own system prompt
  /// ends with an identity guard ("Never speak, think, act, or write dialogue
  /// for the user"), which fights an instruction to describe the scene, and
  /// reusing it would risk the model writing *in character* rather than writing a
  /// picture prompt.
  ///
  /// "Think first, then answer" is stated explicitly because the call runs with
  /// reasoning enabled — the model needs permission to deliberate, and needs to
  /// know deliberation belongs in the reasoning channel rather than mixed into
  /// the answer. Without it the model narrates its process into `content` and the
  /// prompt gets truncated to fit alongside the narration.
  static const String promptWriterSystemPrompt =
      'You are an image-prompt writer for a roleplay scene.\n'
      'Given the final exchange, write ONE vivid text-to-image prompt that '
      'captures the current scene as it would appear in a frame: characters '
      'and their appearance, actions, setting, lighting, and mood.\n'
      'Think through the scene first if you need to, then give the prompt.\n'
      'Rules for the prompt itself:\n'
      '- The prompt is the only thing in your final answer. No preamble, no '
      'analysis, no labels, no quotes around it.\n'
      '- Describe the scene, not the conversation. Do not mention "the user", '
      '"the assistant", or that this is roleplay.\n'
      '- Preserve every physical trait given for a character; never invent or '
      'change one.\n'
      '- Keep it under 120 words.';

  /// The final user turn of the step-1 call.
  ///
  /// Prefixed with `/bypass` so A-PROX takes its pass-through route
  /// (`router::classify_request` checks the bypass flags *before* image-request
  /// detection). Without it, a draft mentioning "draw"/"picture" would trip the
  /// image classifier and silently burn a full image generation. Wire-only — the
  /// user never sees or stores it.
  static const String promptWriterInstruction =
      '/bypass Write the image prompt for the scene depicted above.';

  /// System prompt for the one-time appearance-sheet draft.
  ///
  /// Appearance only: wardrobe and setting change with the scene, and pinning
  /// them would fight the story.
  static const String appearanceWriterSystemPrompt =
      "You extract a character's stable physical appearance from a character "
      'card so it can be kept consistent across generated images.\n'
      'Rules:\n'
      '- Include ONLY stable physical traits: age range, height, build, face, '
      'hair, eyes, skin, distinguishing marks, permanent accessories.\n'
      '- EXCLUDE clothing, outfits, weapons, and setting — those change with '
      'the scene.\n'
      '- EXCLUDE personality, backstory, speech style, and relationships.\n'
      '- If the card states no physical details, reply with exactly: NONE\n'
      '- Otherwise reply with 1-4 short lines of plain descriptive text. No '
      'preamble, no bullets, no name.';

  /// The final user turn of the appearance-draft call.
  static const String appearanceWriterInstruction =
      "/bypass Extract this character's stable physical appearance.\n\n"
      'Character card:\n';

  /// System prompt for the "Detect from avatar" button.
  ///
  /// One word, so it can be parsed without a second call; the user confirms
  /// before it is stored.
  static const String styleDetectorSystemPrompt =
      'You classify the visual style of an image. Reply with exactly one word: '
      'anime, semi-realistic, or photo-realistic.';

  /// The final user turn of the style-detection call.
  static const String styleDetectorInstruction =
      '/bypass Which visual style is this image: anime, semi-realistic, or '
      'photo-realistic? Reply with one word only.';

  /// How many prior messages form the scene context.
  ///
  /// Three exchanges is enough to establish who is doing what and where. More
  /// pushes the actual scene further from the centre of the enhancer's attention
  /// and invites it to illustrate the wrong moment.
  static const int sceneContextMessageCount = 6;

  /// Token budget for the prompt draft.
  ///
  /// The draft call runs with reasoning **on**, so this has to cover a full
  /// thinking pass *plus* the prompt. Sized generously on purpose: running out
  /// mid-thought truncates the instruction, and a truncated instruction has
  /// produced no image at all with no error to explain why.
  ///
  /// Observed on a 35B MoE: ~2.9k tokens for a typical scene. The headroom is
  /// deliberate — measure real usage before lowering it.
  static const int draftMaxTokens = 16384;

  /// Ceiling on the draft request's wall time.
  ///
  /// Must exceed the budget's worst case: 16384 tokens at a typical 50 tok/s is
  /// ~5.5 minutes, plus prompt evaluation. The shared 60s receive budget is not
  /// remotely enough — it aborts requests the server has already answered, and
  /// the client reports that as an empty result.
  ///
  /// A ceiling, not a cost: the request returns as soon as the model finishes,
  /// which is normally well inside it.
  static const Duration draftTimeout = Duration(minutes: 10);

  /// Builds the history for a scene-image request, ending at [targetIndex].
  ///
  /// Returns the last few completed conversation messages plus a synthetic final
  /// user turn carrying the `/image` command. The identity reference is *not*
  /// embedded here — it travels in [RequestOptions.referenceImage] so it is
  /// attached to exactly the right message by the transport layer.
  ///
  /// Variants, streaming turns and empty messages are filtered out: the enhancer
  /// reads this as a scene description, and a half-finished or duplicated
  /// exchange would only muddy it.
  static List<ChatMessage> buildSceneHistory({
    required List<ChatMessage> messages,
    required int targetIndex,
    required String imagePrompt,
  }) {
    final start = targetIndex - sceneContextMessageCount + 1;
    final from = start < 0 ? 0 : start;
    final target = messages[targetIndex];

    final context = messages
        .sublist(from, targetIndex + 1)
        .where((m) =>
            (m.role == MessageRole.user || m.role == MessageRole.assistant) &&
            m.status == MessageStatus.completed &&
            m.content.trim().isNotEmpty)
        .toList();

    return [
      ...context,
      ChatMessage(
        threadId: target.threadId,
        role: MessageRole.user,
        content: '/image $imagePrompt',
        status: MessageStatus.completed,
      ),
    ];
  }

  /// The `/image` directive for a drafted scene prompt.
  ///
  /// Phrased as a *new picture of this subject in a new scene* because the
  /// enhancer's system prompt is an image-**editing** prompt: it will otherwise
  /// try to preserve the reference portrait's own pose and background instead of
  /// placing the character in the scene being described.
  static String imageCommand({
    required String characterName,
    required String draftedPrompt,
    VisualTheme theme = VisualTheme.none,
    String? appearance,
  }) {
    final buffer = StringBuffer(
      'A new picture of $characterName in a new scene, not an edit of the '
      'attached reference image. $draftedPrompt',
    );
    if (appearance != null && appearance.trim().isNotEmpty) {
      buffer.write(
        ' Keep these appearance traits exactly: ${appearance.trim()}.',
      );
    }
    if (theme.isSet) {
      buffer.write(' Render in a ${theme.label.toLowerCase()} style.');
    }
    return buffer.toString();
  }
}
