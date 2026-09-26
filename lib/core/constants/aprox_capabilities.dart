/// Capability tags a server can advertise in its `/health` response.
///
/// A-PROX reports these in `health_check`; every other OpenAI-compatible backend
/// reports nothing, so [ServerProfile.capabilities] stays empty and all
/// A-PROX-only features remain hidden.
class AproxCapabilities {
  /// The server is A-PROX and exposes the RAG store. Doubles as the
  /// "this is A-PROX" test, since RAG is always present on A-PROX.
  static const String rag = 'rag';

  /// `[image_generation]` is enabled — `/image` and `image_style` work.
  static const String image = 'image';

  /// `[file_generation]` is enabled — `/file` works.
  static const String file = 'file';

  /// Every capability A-PROX can advertise. Used to parse a `/health` payload
  /// without hardcoding the list at the call site.
  static const Set<String> all = {rag, image, file};
}

/// Which visual style a character is rendered in.
///
/// The wire value is sent as A-PROX's `image_style` request field and resolved
/// against its `[image_generation.styles]` table, where it contributes a prompt
/// suffix and a negative prompt applied *after* the prompt enhancer rewrites the
/// prompt. A style therefore cannot be diluted by the model.
///
/// [none] is the default: no directive is sent and the model's own choice
/// stands until the user picks one.
enum VisualTheme {
  none(null, 'Not set'),
  anime('anime', 'Anime'),
  semiRealistic('semi-realistic', 'Semi-realistic'),
  photoRealistic('photo-realistic', 'Photo-realistic');

  const VisualTheme(this.wireValue, this.label);

  /// The key A-PROX resolves in `[image_generation.styles]`, or null when the
  /// user has not chosen a style.
  final String? wireValue;

  /// Human-readable label for the settings dropdown.
  final String label;

  bool get isSet => wireValue != null;

  static VisualTheme fromWire(String? value) {
    if (value == null) return VisualTheme.none;
    final normalized = value.trim().toLowerCase();
    for (final theme in VisualTheme.values) {
      if (theme.wireValue == normalized) return theme;
    }
    return VisualTheme.none;
  }
}
