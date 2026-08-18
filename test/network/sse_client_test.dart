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

    test('Correctly parses llama.cpp native /completion stream chunks with timings', () async {
      final sseData = [
        'data: {"content":"Testing","stop":false}\n\n',
        'data: {"content":" 123","stop":true,"timings":{"prompt_n":5,"predicted_n":10,"prompt_ms":100.0,"predicted_ms":200.0,"predicted_per_second":50.0}}\n\n',
      ];

      final controller = StreamController<List<int>>();
      for (final chunk in sseData) {
        controller.add(utf8.encode(chunk));
      }
      controller.close();

      final chunks = await SseClient.parseStream(controller.stream).toList();

      expect(chunks.length, equals(2));
      expect(chunks[0].text, equals('Testing'));
      expect(chunks[1].text, equals(' 123'));
      expect(chunks[1].isDone, isTrue);
      expect(chunks[1].metrics?.tokensPerSecond, equals(50.0));
      expect(chunks[1].metrics?.completionTokens, equals(10));
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
  });
}
