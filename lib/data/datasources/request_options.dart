import 'dart:typed_data';

/// Per-request options that only apply to A-PROX backends.
///
/// Defaults are inert, so every plain llama.cpp / OpenAI request is byte-for-byte
/// what it was before these features existed.
class RequestOptions {
  /// Replaces the `model` field with a routing alias for this request only.
  ///
  /// [aproxRagModelAlias] selects A-PROX's RAG-augmented route: A-PROX
  /// retrieves memories from the collection named in [rag], injects them into
  /// the latest user message, and swaps the alias back to its configured
  /// upstream model before forwarding. `ServerConfig.selectedModel` is never
  /// mutated.
  final String? modelOverride;

  /// A-PROX retrieval tuning: `{'collection': ..., 'top_k': ..., 'min_score': ...}`.
  ///
  /// The collection is what keeps a roleplay session's memories out of the same
  /// namespace as the user's indexed documents — A-PROX searches *every*
  /// collection when no filter is given.
  final Map<String, dynamic>? rag;

  /// Any other A-PROX-only body fields, e.g. `{'image_style': 'anime'}`.
  final Map<String, dynamic>? extraBody;

  /// Tags every outgoing message with `"roleplay": true`, which makes A-PROX
  /// restrict the armed tool set to memory retrieval and image generation.
  final bool roleplayMode;

  /// Image bytes attached to the **final user message** of the request, as an
  /// `image_url` content part.
  /// This is what selects A-PROX's image-to-image workflow, which is
  /// Qwen-Image-Edit-style reference conditioning — the reference conditions
  /// the subject's identity, which is how a character keeps the same face across
  /// generated scenes. The bytes must be PNG/JPEG/WebP; anything else is
  /// silently ignored by A-PROX's format sniffing and the request degrades to
  /// text-to-image.
  ///
  /// Carried here rather than on a `ChatMessage` because the reference is a
  /// transient property of one synthetic request, not something that should be
  /// persisted with a message.
  final Uint8List? referenceImage;

  /// MIME type for [referenceImage]. Sniffed from the bytes when omitted.
  final String? referenceImageMime;

  /// Asks A-PROX to return the image artifact and stop — skipping the vision
  /// caption turn and the final synthesis turn.
  ///
  /// Both of those exist to produce *text* about the picture. A client that
  /// discards the text (this app streams scene images with
  /// `StreamTextMode.discard`) would pay two extra upstream generations for
  /// nothing — measured at ~85s on a 35B model, a large fraction of the
  /// request. The `delta.image_url` event is emitted by A-PROX itself, so the
  /// artifact does not depend on either turn.
  final bool imageOnly;

  /// Overrides the client's 60s response-header budget for this request.
  ///
  /// Only needed where the server holds a request open for minutes *before*
  /// responding at all. A-PROX's `/image` is the case that matters: it stops
  /// llama.cpp, cold-starts ComfyUI, runs the diffusion job and restarts
  /// llama.cpp before emitting any headers (~195s measured). Without this the
  /// client gives up at 60s and reports "no image received" while the server has
  /// already written a good image to disk.
  ///
  /// A cap rather than a cost — the request completes as soon as the job does.
  /// The streamed body itself is bounded by [CancelToken] / user stop, not here.
  final Duration? streamTimeout;

  const RequestOptions({
    this.modelOverride,
    this.rag,
    this.extraBody,
    this.roleplayMode = false,
    this.referenceImage,
    this.referenceImageMime,
    this.imageOnly = false,
    this.streamTimeout,
  });

  /// Wall-time ceiling for a scene-image request, from request send to the
  /// arrival of response headers.
  ///
  /// Comfortably above the observed ~195s (≈43s of agentic routing plus a
  /// 150.8s ComfyUI job that included a cold start and model load). The first
  /// generation after a launch is the slow one; later jobs reuse the loaded
  /// models, so this is sized for the cold path rather than the warm one.
  static const Duration sceneImageStreamTimeout = Duration(minutes: 10);

  static const RequestOptions none = RequestOptions();

  /// The `model` value that routes a request through A-PROX's RAG search.
  static const String aproxRagModelAlias = 'a-prox-rag';

  /// Options for a roleplay turn whose memories live on the A-PROX server.
  factory RequestOptions.serverSideRag({
    required String collection,
    required int topK,
    required double minScore,
    String? modelAlias,
  }) {
    return RequestOptions(
      modelOverride: modelAlias ?? aproxRagModelAlias,
      rag: {
        'collection': collection,
        'top_k': topK,
        'min_score': minScore,
      },
      roleplayMode: true,
    );
  }

  /// Options for a scene-image generation request.
  ///
  /// Deliberately **not** [roleplayMode]: the tool restriction would arm
  /// `rag_search` alongside `image_generate`, and this request is purely about
  /// making a picture. `/image` already forces a loop with only that tool armed.
  factory RequestOptions.sceneImage({
    String? style,
    Uint8List? referenceImage,
    String? referenceImageMime,
  }) {
    return RequestOptions(
      extraBody: style == null ? null : {'image_style': style},
      referenceImage: referenceImage,
      referenceImageMime: referenceImageMime,
      // The caller streams this with StreamTextMode.discard, so the caption and
      // synthesis turns would be thrown away.
      imageOnly: true,
      // A-PROX withholds every header until the diffusion job is done, which
      // takes minutes. Without this the shared 60s budget aborts the client
      // after the image already exists.
      streamTimeout: sceneImageStreamTimeout,
    );
  }

  RequestOptions copyWith({
    String? modelOverride,
    Map<String, dynamic>? rag,
    Map<String, dynamic>? extraBody,
    bool? roleplayMode,
    Uint8List? referenceImage,
    String? referenceImageMime,
    bool? imageOnly,
    Duration? streamTimeout,
  }) {
    return RequestOptions(
      modelOverride: modelOverride ?? this.modelOverride,
      rag: rag ?? this.rag,
      extraBody: extraBody ?? this.extraBody,
      roleplayMode: roleplayMode ?? this.roleplayMode,
      referenceImage: referenceImage ?? this.referenceImage,
      referenceImageMime: referenceImageMime ?? this.referenceImageMime,
      imageOnly: imageOnly ?? this.imageOnly,
      streamTimeout: streamTimeout ?? this.streamTimeout,
    );
  }
}
