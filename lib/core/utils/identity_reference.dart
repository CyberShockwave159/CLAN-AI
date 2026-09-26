import 'package:clan_ai/core/constants/aprox_capabilities.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Where a character's identity reference image came from.
///
/// Recorded so the UI can explain *why* a reference is being used — a card
/// avatar conditioning every scene is a reasonable default, but an invisible
/// one is how a user ends up wondering why their character keeps changing face.
enum IdentityReferenceSource {
  /// The portrait the user generated and approved for this purpose.
  approvedPortrait,

  /// The character card's avatar, used as a fallback.
  characterAvatar,

  /// An image the user picked from a previous generation to refine from.
  priorGeneration,
}

/// A reference image to condition scene generation on.
class IdentityReference {
  final Uint8List bytes;
  final IdentityReferenceSource source;

  const IdentityReference({required this.bytes, required this.source});
}

/// Resolves the reference image that keeps a character recognizable across
/// generated scenes.
///
/// A-PROX's image-to-image path is Qwen-Image-Edit-style *reference
/// conditioning*: the reference is passed to the text encoder as an image token
/// rather than used to seed a latent (`denoise: 1`, `latent_image` taken from
/// the encoder), which is the mechanism that preserves a subject's face in a new
/// scene. The i2i workflow is selected automatically whenever the request's final
/// user message carries an `image_url` part, so all this class must do is
/// produce suitable bytes.
///
/// **The bytes must be PNG, JPEG or WebP.** A-PROX sniffs magic bytes
/// (`imagegen::guess_format`) and silently falls through to text-to-image for
/// anything else — an AVIF avatar would yield a plausible image that ignored the
/// reference entirely, with no error to explain why.
class IdentityReferenceResolver {
  /// Longest edge of a reference image.
  ///
  /// The reference conditions identity, not fine detail, and it is base64-inlined
  /// into the JSON request body — so 512px is ample and keeps the payload small.
  static const int maxReferenceEdge = 512;

  /// Resolves the reference to use for [character].
  ///
  /// Priority: an approved portrait (chosen for this purpose), then the
  /// character card's avatar. Returns null when the character has neither, which
  /// is the signal for the caller to offer portrait generation rather than
  /// silently producing an inconsistent image.
  static IdentityReference? forCharacter(CharacterProfile character) {
    final portrait = character.identityPortraitData;
    if (portrait != null && portrait.isNotEmpty) {
      return IdentityReference(
        bytes: normalizeForReference(portrait),
        source: IdentityReferenceSource.approvedPortrait,
      );
    }
    final avatar = character.avatarData;
    if (avatar != null && avatar.isNotEmpty) {
      return IdentityReference(
        bytes: normalizeForReference(avatar),
        source: IdentityReferenceSource.characterAvatar,
      );
    }
    return null;
  }

  /// Wraps bytes the user picked from a previous generation.
  static IdentityReference fromPriorGeneration(Uint8List bytes) {
    return IdentityReference(
      bytes: normalizeForReference(bytes),
      source: IdentityReferenceSource.priorGeneration,
    );
  }

  /// Whether [bytes] are in a format A-PROX will accept as a reference.
  static bool isSupportedFormat(Uint8List bytes) {
    return MessageAttachmentStore.mimeTypeFromBytes(bytes) != null;
  }

  /// Prepares [bytes] for use as a reference: downscale to
  /// [maxReferenceEdge], transcoding unsupported formats to JPEG.
  ///
  /// Returns the input unchanged if it cannot be decoded. That degrades the
  /// request to text-to-image instead of failing it — a scene without a
  /// consistent face beats no scene at all — but the caller can detect it via
  /// [isSupportedFormat] and warn.
  static Uint8List normalizeForReference(Uint8List bytes) {
    if (bytes.isEmpty) return bytes;
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      final longestEdge =
          decoded.width > decoded.height ? decoded.width : decoded.height;
      if (longestEdge <= maxReferenceEdge &&
          _isJpeg(bytes)) {
        return bytes; // Already small enough and in an accepted format.
      }
      final scaled = longestEdge > maxReferenceEdge
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height
                  ? maxReferenceEdge
                  : (decoded.width * maxReferenceEdge / longestEdge).round(),
              height: decoded.height > decoded.width
                  ? maxReferenceEdge
                  : (decoded.height * maxReferenceEdge / longestEdge).round(),
            )
          : decoded;
      // JPEG is the safest interchange format here: universally accepted by
      // A-PROX, and small for a photographic portrait.
      final encoded = img.encodeJpg(scaled, quality: 88);
      return Uint8List.fromList(encoded);
    } catch (e) {
      debugPrint('[IdentityReference] could not normalize image: $e');
      return bytes;
    }
  }

  static bool _isJpeg(Uint8List bytes) =>
      MessageAttachmentStore.mimeTypeFromBytes(bytes) == 'image/jpeg';
}

/// Builds the instruction for generating a character's reference portrait.
///
/// A bust shot conditions identity far better than a full scene, so the portrait
/// request is deliberately *not* a scene prompt. Phrased to suit the t2i prompt
/// enhancer, which treats every request as an image-*editing* task and expects a
/// subject already in frame.
class PortraitPrompt {
  /// The style phrase matching [theme], used both in the portrait instruction
  /// and (via `image_style`) at the workflow level.
  static String stylePhrase(VisualTheme theme) {
    return switch (theme) {
      VisualTheme.anime =>
        'anime key visual, cel-shaded, clean line art, flat colour blocking',
      VisualTheme.semiRealistic =>
        'semi-realistic digital illustration, soft painterly shading',
      VisualTheme.photoRealistic =>
        'photorealistic portrait photograph, natural skin texture, 50mm lens',
      VisualTheme.none => 'clear, well-lit portrait',
    };
  }

  /// Builds the portrait-generation instruction for [characterName].
  ///
  /// Includes the appearance sheet when present so the approved portrait matches
  /// the canonical description rather than the model's own idea of the
  /// character.
  static String build({
    required String characterName,
    required VisualTheme theme,
    String? appearance,
  }) {
    final appearanceLine = (appearance == null || appearance.trim().isEmpty)
        ? ''
        : ' Subject: ${appearance.trim()}.';
    return 'Generate a centred head-and-shoulders character reference portrait '
        'of $characterName. Front-facing, neutral expression, plain neutral '
        'background, soft even lighting, sharp focus on the face. '
        '${stylePhrase(theme)}.$appearanceLine';
  }
}
