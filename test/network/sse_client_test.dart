import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:clan_ai/core/network/sse_client.dart';

void main() {
  group('SseClient SSE Streaming Tests', () {
    test('Correctly parses OpenAI streaming chat completion delta chunks', () async {
      final sseData = [
        'data: {"id":"chatcmpl-1","choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}\n\n',
        'data: {"id":"chatcmpl-1","choices":[{"delta":{"content":" world"},"finish_reason":null}]}\n\n',
        'data: {"id":"chatcmpl-1","choices":[{"delta":{"content":"!"},"finish_reason":"stop"}]}\n\n',
        'data: [DONE]\n\n',
      ];

      final controller = StreamController<List<int>>();
      for (final chunk in sseData) {
        controller.add(utf8.encode(chunk));
      }
      controller.close();

      final chunks = await SseClient.parseStream(controller.stream).toList();

      expect(chunks.length, greaterThanOrEqualTo(3));
      final combinedText = chunks.map((c) => c.text).join();
      expect(combinedText, equals('Hello world!'));
      expect(chunks.last.isDone, isTrue);
    });

    test('Ignores SSE ping comments and handles multi-line chunks', () async {
      final sseData = [
        ': ping\n\n',
        'data: {"choices":[{"delta":{"content":"Multi"}\n',
        'data: ,"finish_reason":null}]}\n\n',
        'data: [DONE]\n\n',
      ];

      final controller = StreamController<List<int>>();
      for (final chunk in sseData) {
        controller.add(utf8.encode(chunk));
      }
      controller.close();

      final chunks = await SseClient.parseStream(controller.stream).toList();

      expect(chunks.isNotEmpty, isTrue);
      expect(chunks[0].text, equals('Multi'));
    });

    test('Correctly extracts reasoning_content, reasoning, and thought from OpenAI delta', () async {
      final sseData = [
        'data: {"choices":[{"delta":{"reasoning_content":"Let me calculate"},"finish_reason":null}]}\n\n',
        'data: {"choices":[{"delta":{"reasoning":" 2 + 2"},"finish_reason":null}]}\n\n',
        'data: {"choices":[{"delta":{"content":"The answer is 4."},"finish_reason":"stop"}]}\n\n',
        'data: [DONE]\n\n',
      ];

      final controller = StreamController<List<int>>();
      for (final chunk in sseData) {
        controller.add(utf8.encode(chunk));
      }
      controller.close();

      final chunks = await SseClient.parseStream(controller.stream).toList();

      final reasoning = chunks.map((c) => c.reasoning ?? '').join();
      final text = chunks.map((c) => c.text).join();

      expect(reasoning, equals('Let me calculate 2 + 2'));
      expect(text, equals('The answer is 4.'));
    });

    test('filterReasoning extracts <think> tags into reasoning when enabled', () async {
      final inputChunks = [
        const StreamChunk(text: '<think>I should check '),
        const StreamChunk(text: 'the formula.</think>\nResult: 42'),
        const StreamChunk(text: '', isDone: true),
      ];

      final filtered = await SseClient.filterReasoning(
        Stream.fromIterable(inputChunks),
        enableReasoning: true,
      ).toList();

      final reasoning = filtered.map((c) => c.reasoning ?? '').join();
      final text = filtered.map((c) => c.text).join();

      expect(reasoning, equals('I should check the formula.'));
      expect(text, equals('Result: 42'));
    });

    test('filterReasoning strips <think> tags and discards reasoning when disabled', () async {
      final inputChunks = [
        const StreamChunk(text: '<think>Secret inner thoughts</think>\nVisible answer.'),
        const StreamChunk(text: '', reasoning: 'hidden reasoning', isDone: false),
        const StreamChunk(text: '', isDone: true),
      ];

      final filtered = await SseClient.filterReasoning(
        Stream.fromIterable(inputChunks),
        enableReasoning: false,
      ).toList();

      final reasoning = filtered.map((c) => c.reasoning ?? '').join();
      final text = filtered.map((c) => c.text).join();

      expect(reasoning, isEmpty);
      expect(text, equals('Visible answer.'));
    });
  });
}
