/// Generation hyperparameters for llama.cpp / OpenAI completions.
class GenerationParams {
  final double temperature;
  final double topP;
  final int topK;
  final double minP;
  final double repeatPenalty;
  final double presencePenalty;
  final double frequencyPenalty;
  final int maxTokens;
  final int contextSize;
  final List<String> stopSequences;
  final String? grammar;

  const GenerationParams({
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.minP = 0.05,
    this.repeatPenalty = 1.1,
    this.presencePenalty = 0.0,
    this.frequencyPenalty = 0.0,
    this.maxTokens = 4096,
    this.contextSize = 4096,
    this.stopSequences = const [],
    this.grammar,
  });

  GenerationParams copyWith({
    double? temperature,
    double? topP,
    int? topK,
    double? minP,
    double? repeatPenalty,
    double? presencePenalty,
    double? frequencyPenalty,
    int? maxTokens,
    int? contextSize,
    List<String>? stopSequences,
    String? grammar,
  }) {
    return GenerationParams(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      minP: minP ?? this.minP,
      repeatPenalty: repeatPenalty ?? this.repeatPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      maxTokens: maxTokens ?? this.maxTokens,
      contextSize: contextSize ?? this.contextSize,
      stopSequences: stopSequences ?? this.stopSequences,
      grammar: grammar ?? this.grammar,
    );
  }

  Map<String, dynamic> toOpenAiPayload({
    required List<Map<String, dynamic>> messages,
    required String model,
    bool stream = true,
  }) {
    final payload = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': stream,
      'temperature': temperature,
      'top_p': topP,
      'presence_penalty': presencePenalty,
      'frequency_penalty': frequencyPenalty,
    };

    // max_tokens: 0 means unlimited (omit from payload for OpenAI)
    if (maxTokens > 0) {
      payload['max_tokens'] = maxTokens;
    }

    if (stopSequences.isNotEmpty) {
      payload['stop'] = stopSequences;
    }
    return payload;
  }

  Map<String, dynamic> toLlamaNativePayload({
    required String prompt,
    bool stream = true,
  }) {
    final payload = <String, dynamic>{
      'prompt': prompt,
      'stream': stream,
      'temperature': temperature,
      'top_p': topP,
      'top_k': topK,
      'min_p': minP,
      'repeat_penalty': repeatPenalty,
      'n_ctx': contextSize,
    };

    // n_predict: 0 means unlimited in llama.cpp
    if (maxTokens >= 0) {
      payload['n_predict'] = maxTokens;
    }

    if (stopSequences.isNotEmpty) {
      payload['stop'] = stopSequences;
    }
    if (grammar != null && grammar!.isNotEmpty) {
      payload['grammar'] = grammar;
    }
    return payload;
  }

  Map<String, dynamic> toMap() {
    return {
      'temperature': temperature,
      'top_p': topP,
      'top_k': topK,
      'min_p': minP,
      'repeat_penalty': repeatPenalty,
      'presence_penalty': presencePenalty,
      'frequency_penalty': frequencyPenalty,
      'max_tokens': maxTokens,
      'context_size': contextSize,
      'stop_sequences': stopSequences,
      'grammar': grammar,
    };
  }

  factory GenerationParams.fromMap(Map<String, dynamic> map) {
    return GenerationParams(
      temperature: (map['temperature'] as num?)?.toDouble() ?? 0.7,
      topP: (map['top_p'] as num?)?.toDouble() ?? 0.9,
      topK: (map['top_k'] as num?)?.toInt() ?? 40,
      minP: (map['min_p'] as num?)?.toDouble() ?? 0.05,
      repeatPenalty: (map['repeat_penalty'] as num?)?.toDouble() ?? 1.1,
      presencePenalty: (map['presence_penalty'] as num?)?.toDouble() ?? 0.0,
      frequencyPenalty: (map['frequency_penalty'] as num?)?.toDouble() ?? 0.0,
      maxTokens: (map['max_tokens'] as num?)?.toInt() ?? 4096,
      contextSize: (map['context_size'] as num?)?.toInt() ?? 4096,
      stopSequences: (map['stop_sequences'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      grammar: map['grammar'] as String?,
    );
  }
}
