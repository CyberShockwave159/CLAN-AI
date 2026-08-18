/// Model metadata from /v1/models and /props endpoints.
class ModelInfo {
  final String id;
  final String name;
  final String? ownedBy;
  final int? contextLength;
  final String? format;
  final String? quantization;
  final Map<String, dynamic>? rawProps;

  const ModelInfo({
    required this.id,
    required this.name,
    this.ownedBy,
    this.contextLength,
    this.format,
    this.quantization,
    this.rawProps,
  });

  factory ModelInfo.fromOpenAiJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? 'default';
    return ModelInfo(
      id: id,
      name: id,
      ownedBy: json['owned_by'] as String?,
    );
  }

  factory ModelInfo.fromLlamaProps(Map<String, dynamic> json) {
    final modelName = json['model'] as String? ?? json['name'] as String? ?? 'llama.cpp Model';
    final nCtx = (json['default_generation_settings']?['n_ctx'] as num?)?.toInt() ??
        (json['n_ctx'] as num?)?.toInt();

    return ModelInfo(
      id: modelName,
      name: modelName,
      contextLength: nCtx,
      rawProps: json,
    );
  }
}
