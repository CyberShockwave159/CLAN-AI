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

    test('parses delta.image_url object form with caption text', () async {
      final sseData = [
        'data: {"choices":[{"delta":{"image_url":{"url":"http://localhost:8080/image.png"}},"finish_reason":null}]}\n\n',
        'data: {"choices":[{"delta":{"content":"Here is the image."},"finish_reason":"stop"}]}\n\n',
        'data: [DONE]\n\n',
      ];

      final chunks = await _parseChunks(sseData);

      expect(chunks[0].imageUrl, equals('http://localhost:8080/image.png'));
      expect(chunks[0].text, isEmpty);
      expect(chunks.map((c) => c.text).join(), equals('Here is the image.'));
    });

    test('parses delta.image_url bare-string form', () async {
      final sseData = [
        'data: {"choices":[{"delta":{"image_url":"http://host/banner.jpg"},"finish_reason":null}]}\n\n',
        'data: [DONE]\n\n',
      ];

      final chunks = await _parseChunks(sseData);
      expect(chunks[0].imageUrl, equals('http://host/banner.jpg'));
    });

    test('parses delta.file_url with name and mime fields', () async {
      final sseData = [
        'data: {"choices":[{"delta":{"file_url":{"url":"http://host/export.csv","name":"export.csv","mime":"text/csv"}},"finish_reason":null}]}\n\n',
        'data: {"choices":[{"delta":{"content":"Your export."},"finish_reason":"stop"}]}\n\n',
        'data: [DONE]\n\n',
      ];

      final chunks = await _parseChunks(sseData);

      expect(chunks[0].fileUrl, equals('http://host/export.csv'));
      expect(chunks[0].fileName, equals('export.csv'));
      expect(chunks[0].fileMime, equals('text/csv'));
      expect(chunks.map((c) => c.text).join(), equals('Your export.'));
    });

    test('parses outer message.file_url on a non-streaming style response', () async {
      final sseData = [
        'data: {"choices":[{"message":{"content":"Done","file_url":{"url":"http://host/data.pdf","name":"data.pdf","mime":"application/pdf"}},"finish_reason":"stop"}]}\n\n',
      ];

      final chunks = await _parseChunks(sseData);

      expect(chunks.single.fileUrl, equals('http://host/data.pdf'));
      expect(chunks.single.fileName, equals('data.pdf'));
      expect(chunks.single.fileMime, equals('application/pdf'));
      expect(chunks.single.text, equals('Done'));
    });

    test('filterReasoning forwards artifacts across reconstructed chunks', () async {
      final inputChunks = [
        const StreamChunk(
          text: ' thinkingdraft response',
          imageUrl: 'http://host/img.png',
        ),
        const StreamChunk(
          text: '',
          isDone: true,
          fileUrl: 'http://host/doc.txt',
          fileName: 'doc.txt',
          fileMime: 'text/plain',
        ),
      ];

      final filtered = await SseClient.filterReasoning(
        Stream.fromIterable(inputChunks),
        enableReasoning: true,
      ).toList();

      expect(filtered.where((c) => c.imageUrl != null), hasLength(1));
      expect(filtered.first.imageUrl, equals('http://host/img.png'));
      expect(filtered.last.fileUrl, equals('http://host/doc.txt'));
      expect(filtered.last.fileName, equals('doc.txt'));
      expect(filtered.last.fileMime, equals('text/plain'));
    });
  });
}

Future<List<StreamChunk>> _parseChunks(List<String> sseData) async {
  final controller = StreamController<List<int>>();
  for (final chunk in sseData) {
    controller.add(utf8.encode(chunk));
  }
  controller.close();
  return SseClient.parseStream(controller.stream).toList();
}
