import 'dart:async';
import 'dart:convert';
import 'package:clan_ai/core/errors/app_exception.dart';

/// Metrics captured during token generation
class StreamMetrics {
  final int promptTokens;
  final int completionTokens;
  final double promptEvalTimeSec;
  final double generationTimeSec;
  final double tokensPerSecond;
  final int timeToFirstTokenMs;

  const StreamMetrics({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.promptEvalTimeSec = 0.0,
    this.generationTimeSec = 0.0,
    this.tokensPerSecond = 0.0,
    this.timeToFirstTokenMs = 0,
  });

  factory StreamMetrics.fromLlamaTimings(Map<String, dynamic> timings, int ttftMs) {
    final promptN = (timings['prompt_n'] as num?)?.toInt() ?? 0;
    final predictedN = (timings['predicted_n'] as num?)?.toInt() ?? 0;
    final promptMs = (timings['prompt_ms'] as num?)?.toDouble() ?? 0.0;
    final predictedMs = (timings['predicted_ms'] as num?)?.toDouble() ?? 0.0;
    final predictedPerSec = (timings['predicted_per_second'] as num?)?.toDouble() ??
        (predictedMs > 0 ? (predictedN / (predictedMs / 1000.0)) : 0.0);

    return StreamMetrics(
      promptTokens: promptN,
      completionTokens: predictedN,
      promptEvalTimeSec: promptMs / 1000.0,
      generationTimeSec: predictedMs / 1000.0,
      tokensPerSecond: predictedPerSec,
      timeToFirstTokenMs: ttftMs,
    );
  }
}

/// A streaming token chunk emitted by [SseClient].
class StreamChunk {
  final String text;
  final bool isDone;
  final StreamMetrics? metrics;
  final String? finishReason;
  final String? reasoning;

  /// A-PROX image artifact (`delta.image_url.url` / outer `image_url.url`) that
  /// arrived ahead of (or instead of) text. One-shot: the producer
  /// (StreamMutationMixin) captures it at most once per response.
  final String? imageUrl;

  /// A-PROX file artifact (`delta.file_url` / outer `file_url`).
  final String? fileUrl;
  final String? fileName;
  final String? fileMime;

  const StreamChunk({
    required this.text,
    this.isDone = false,
    this.metrics,
    this.finishReason,
    this.reasoning,
    this.imageUrl,
    this.fileUrl,
    this.fileName,
    this.fileMime,
  });

  /// When this chunk also carries text/reasoning, splits them apart so the
  /// single artifact field survives a later copyWith on the bubble. Never used
  /// by the parser itself (it emits artifact+text chunks wholesale); reserved
  /// for the mixin's artifact-embedding step.
  bool get hasArtifact => imageUrl != null || fileUrl != null;
}

/// Cancellation token to cancel active HTTP/SSE streams.
class CancelToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in _listeners) {
      listener();
    }
    _listeners.clear();
  }

  void onCancel(void Function() listener) {
    if (_isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}

/// High-performance Server-Sent Events parser for OpenAI-compatible streaming responses.
class SseClient {
  /// Transforms a raw byte stream into a stream of [StreamChunk]s.
  static Stream<StreamChunk> parseStream(
    Stream<List<int>> byteStream, {
    CancelToken? cancelToken,
  }) async* {
    final stopwatch = Stopwatch()..start();
    int? timeToFirstTokenMs;
    int tokenCount = 0;

    final lineStream = byteStream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    bool isCancelled = false;
    cancelToken?.onCancel(() {
      isCancelled = true;
    });

    final dataBuffer = StringBuffer();

    await for (final line in lineStream) {
      if (isCancelled || (cancelToken?.isCancelled ?? false)) {
        throw const RequestCancelledException();
      }

      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) {
        // End of an SSE message block
        if (dataBuffer.isNotEmpty) {
          final chunk = _processDataBlock(
            dataBuffer.toString(),
            stopwatch,
            timeToFirstTokenMs,
            tokenCount,
          );
          dataBuffer.clear();

          if (chunk != null) {
            if (timeToFirstTokenMs == null && chunk.text.isNotEmpty) {
              timeToFirstTokenMs = stopwatch.elapsedMilliseconds;
            }
            if (chunk.text.isNotEmpty) {
              tokenCount++;
            }
            yield chunk;
            if (chunk.isDone) {
              return;
            }
          }
        }
        continue;
      }

      // Ignore SSE comments (e.g., ": ping")
      if (trimmedLine.startsWith(':')) {
        continue;
      }

      if (trimmedLine.startsWith('data:')) {
        final dataContent = trimmedLine.substring(5).trim();
        if (dataBuffer.isNotEmpty) {
          dataBuffer.write('\n');
        }
        dataBuffer.write(dataContent);
      }
    }

    // Process any lingering buffer at the end of the stream
    if (dataBuffer.isNotEmpty) {
      final chunk = _processDataBlock(
        dataBuffer.toString(),
        stopwatch,
        timeToFirstTokenMs,
        tokenCount,
      );
      if (chunk != null) {
        yield chunk;
      }
    }
  }

  /// Transforms a stream of [StreamChunk]s by extracting or stripping inline thinking tags
  /// (e.g. `<think>...</think>`, `<thought>...</thought>`, `<reasoning>...</reasoning>`)
  /// and respecting [enableReasoning].
  static Stream<StreamChunk> filterReasoning(
    Stream<StreamChunk> source, {
    required bool enableReasoning,
  }) async* {
    bool insideThinkTag = false;
    String partialBuffer = '';

    const openTags = ['<think>', '<thought>', '<reasoning>'];
    const closeTags = ['</think>', '</thought>', '</reasoning>'];

    int? findPendingTagPrefix(String buffer, List<String> tags) {
      for (int len = 1; len <= buffer.length && len <= 12; len++) {
        final suffix = buffer.substring(buffer.length - len);
        for (final tag in tags) {
          if (tag.startsWith(suffix) && tag != suffix) {
            return buffer.length - len;
          }
        }
      }
      return null;
    }

    await for (final chunk in source) {
      // 1. If chunk already has dedicated reasoning field
      if (chunk.reasoning != null && chunk.reasoning!.isNotEmpty) {
        if (enableReasoning) {
          yield _copyArtifacts(
            StreamChunk(
              text: '',
              reasoning: chunk.reasoning,
              isDone: false,
            ),
            chunk,
          );
        }
      }

      // 2. If chunk has text, process inline tags
      if (chunk.text.isNotEmpty) {
        partialBuffer += chunk.text;

        while (partialBuffer.isNotEmpty) {
          if (!insideThinkTag) {
            int earliestIdx = -1;
            String? matchedTag;
            for (final tag in openTags) {
              final idx = partialBuffer.indexOf(tag);
              if (idx != -1 && (earliestIdx == -1 || idx < earliestIdx)) {
                earliestIdx = idx;
                matchedTag = tag;
              }
            }

            if (earliestIdx != -1 && matchedTag != null) {
              final textBefore = partialBuffer.substring(0, earliestIdx);
              if (textBefore.isNotEmpty) {
                yield _copyArtifacts(StreamChunk(text: textBefore), chunk);
              }
              partialBuffer = partialBuffer.substring(earliestIdx + matchedTag.length);
              insideThinkTag = true;
            } else {
              final prefixStart = findPendingTagPrefix(partialBuffer, openTags);
              if (prefixStart != null) {
                final safeText = partialBuffer.substring(0, prefixStart);
                if (safeText.isNotEmpty) {
                  yield _copyArtifacts(StreamChunk(text: safeText), chunk);
                }
                partialBuffer = partialBuffer.substring(prefixStart);
                break;
              } else {
                yield _copyArtifacts(StreamChunk(text: partialBuffer), chunk);
                partialBuffer = '';
                break;
              }
            }
          } else {
            int earliestIdx = -1;
            String? matchedTag;
            for (final tag in closeTags) {
              final idx = partialBuffer.indexOf(tag);
              if (idx != -1 && (earliestIdx == -1 || idx < earliestIdx)) {
                earliestIdx = idx;
                matchedTag = tag;
              }
            }

            if (earliestIdx != -1 && matchedTag != null) {
              final reasoningBefore = partialBuffer.substring(0, earliestIdx);
              if (enableReasoning && reasoningBefore.isNotEmpty) {
                yield _copyArtifacts(
                  StreamChunk(text: '', reasoning: reasoningBefore),
                  chunk,
                );
              }
              partialBuffer = partialBuffer.substring(earliestIdx + matchedTag.length);
              insideThinkTag = false;
              if (partialBuffer.startsWith('\n')) {
                partialBuffer = partialBuffer.substring(1);
              }
            } else {
              final prefixStart = findPendingTagPrefix(partialBuffer, closeTags);
              if (prefixStart != null) {
                final safeReasoning = partialBuffer.substring(0, prefixStart);
                if (enableReasoning && safeReasoning.isNotEmpty) {
                  yield _copyArtifacts(
                    StreamChunk(text: '', reasoning: safeReasoning),
                    chunk,
                  );
                }
                partialBuffer = partialBuffer.substring(prefixStart);
                break;
              } else {
                if (enableReasoning) {
                  yield _copyArtifacts(
                    StreamChunk(text: '', reasoning: partialBuffer),
                    chunk,
                  );
                }
                partialBuffer = '';
                break;
              }
            }
          }
        }
      }

      // 3. If chunk is done, flush remaining buffer and emit final chunk with metrics
      if (chunk.isDone) {
        if (partialBuffer.isNotEmpty) {
          if (insideThinkTag) {
            if (enableReasoning) {
              yield _copyArtifacts(
                StreamChunk(text: '', reasoning: partialBuffer),
                chunk,
              );
            }
          } else {
            yield _copyArtifacts(StreamChunk(text: partialBuffer), chunk);
          }
          partialBuffer = '';
        }

        yield _copyArtifacts(
          StreamChunk(
            text: '',
            isDone: true,
            finishReason: chunk.finishReason,
            metrics: chunk.metrics,
          ),
          chunk,
        );
      }
    }

    if (partialBuffer.isNotEmpty) {
      if (insideThinkTag) {
        if (enableReasoning) {
          yield StreamChunk(text: '', reasoning: partialBuffer);
        }
      } else {
        yield StreamChunk(text: partialBuffer);
      }
    }
  }

  static StreamChunk? _processDataBlock(
    String rawData,
    Stopwatch stopwatch,
    int? ttftMs,
    int tokenCount,
  ) {
    if (rawData == '[DONE]') {
      final totalElapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
      final tokPerSec = totalElapsedSec > 0 ? tokenCount / totalElapsedSec : 0.0;

      return StreamChunk(
        text: '',
        isDone: true,
        metrics: StreamMetrics(
          completionTokens: tokenCount,
          generationTimeSec: totalElapsedSec,
          tokensPerSecond: tokPerSec,
          timeToFirstTokenMs: ttftMs ?? stopwatch.elapsedMilliseconds,
        ),
      );
    }

    try {
      final dynamic decoded = jsonDecode(rawData);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      // 1. Check for error responses in stream
      if (decoded.containsKey('error')) {
        final err = decoded['error'];
        final errMsg = err is Map ? err['message'] ?? err.toString() : err.toString();
        if (errMsg.toLowerCase().contains('context') || errMsg.toLowerCase().contains('exceed')) {
          throw ContextLimitExceededException(message: errMsg);
        }
        throw AppException(message: errMsg);
      }

      // 2. OpenAI chat completions format: choices[0].delta.content + delta.reasoning / reasoning_content / thought
      if (decoded.containsKey('choices')) {
        final choices = decoded['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final firstChoice = choices.first as Map<String, dynamic>;
          final delta = firstChoice['delta'] as Map<String, dynamic>?;
          final message = firstChoice['message'] as Map<String, dynamic>?;
          final finishReason = firstChoice['finish_reason'] as String?;
          final deltaContent = delta?['content'] as String? ?? '';
          final text = deltaContent.isNotEmpty
              ? deltaContent
              : message?['content'] as String? ?? '';
          final reasoning = delta?['reasoning_content'] as String? ??
              delta?['reasoning'] as String? ??
              delta?['thought'] as String? ??
              firstChoice['reasoning_content'] as String? ??
              firstChoice['reasoning'] as String? ??
              decoded['reasoning_content'] as String? ??
              decoded['reasoning'] as String? ??
              decoded['thought'] as String?;

          final isDone = finishReason != null && finishReason != 'null' && finishReason.isNotEmpty;

          // Check if usage/timings are present in response (e.g. llama.cpp in OpenAI mode)
          StreamMetrics? metrics;
          if (decoded.containsKey('timings') && decoded['timings'] is Map<String, dynamic>) {
            metrics = StreamMetrics.fromLlamaTimings(
              decoded['timings'] as Map<String, dynamic>,
              ttftMs ?? stopwatch.elapsedMilliseconds,
            );
          } else if (isDone) {
            final totalSec = stopwatch.elapsedMilliseconds / 1000.0;
            final tokPerSec = totalSec > 0 ? (tokenCount + (text.isNotEmpty ? 1 : 0)) / totalSec : 0.0;
            metrics = StreamMetrics(
              completionTokens: tokenCount + (text.isNotEmpty ? 1 : 0),
              generationTimeSec: totalSec,
              tokensPerSecond: tokPerSec,
              timeToFirstTokenMs: ttftMs ?? stopwatch.elapsedMilliseconds,
            );
          }

          // A-PROX artifacts: `delta.image_url` / `delta.file_url` (or the
          // outer `message.image_url` / `message.file_url` on non-streaming
          // responses) may be the object form (`{ "url": ... }` /
          // `{ "url", "name", "mime" }`) or a bare URL string. They arrive
          // ahead of (or instead of) the caption text, so capture them once
          // here rather than as a mid-stream join.
          final imageUrl = _artifactUrlOf(_firstNonNull([
            delta?['image_url'],
            firstChoice['image_url'],
            message?['image_url'],
            decoded['image_url'],
          ]));
          final fileArtifact = _firstNonNull([
            delta?['file_url'],
            firstChoice['file_url'],
            message?['file_url'],
            decoded['file_url'],
          ]);
          final fileUrl = _artifactUrlOf(fileArtifact);
          String? fileName;
          String? fileMime;
          if (fileArtifact is Map) {
            final name = fileArtifact['name'];
            final mime = fileArtifact['mime'];
            fileName = name is String && name.isNotEmpty ? name : null;
            fileMime = mime is String && mime.isNotEmpty ? mime : null;
          }

          return StreamChunk(
            text: text,
            isDone: isDone,
            finishReason: finishReason,
            metrics: metrics,
            reasoning: reasoning,
            imageUrl: imageUrl,
            fileUrl: fileUrl,
            fileName: fileName,
            fileMime: fileMime,
          );
        }
      }

      return null;
    } catch (e) {
      if (e is AppException) rethrow;
      // Not a valid JSON payload yet or unrecognized format
      return null;
    }
  }

  /// Re-emits [streamChunk] carrying the A-PROX artifact fields of [source], so
  /// artifact URLs (delta.image_url / delta.file_url) survive the inline-tag
  /// reconstruction instead of being dropped with the source chunk.
  static StreamChunk _copyArtifacts(StreamChunk streamChunk, StreamChunk source) {
    return StreamChunk(
      text: streamChunk.text,
      isDone: streamChunk.isDone,
      finishReason: streamChunk.finishReason,
      metrics: streamChunk.metrics,
      reasoning: streamChunk.reasoning,
      imageUrl: source.imageUrl,
      fileUrl: source.fileUrl,
      fileName: source.fileName,
      fileMime: source.fileMime,
    );
  }

  /// Resolves a bare-string or `{ "url": ... }` A-PROX artifact value to its
  /// URL, or null when the value is absent or malformed.
  static String? _artifactUrlOf(dynamic artifact) {
    if (artifact is String) {
      final trimmed = artifact.trim();
      return trimmed.isNotEmpty ? trimmed : null;
    }
    if (artifact is Map) {
      final url = artifact['url'];
      return url is String && url.trim().isNotEmpty ? url.trim() : null;
    }
    return null;
  }

  /// Returns the first non-null value among [values].
  static dynamic _firstNonNull(List<dynamic> values) {
    for (final value in values) {
      if (value != null) return value;
    }
    return null;
  }
}
