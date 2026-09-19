import 'dart:convert';
import 'dart:io';

import 'package:clan_ai/core/network/http_client.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/data/datasources/llama_api_service.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/test_model_factories.dart';

void main() {
  group('LlamaApiService image attachment serialization', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('clan_ai_img_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    // Minimal valid PNG header bytes (not a full image, just payload bytes).
    final pngBytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4];

    Future<File> writeImage(String name) async {
      final file = File('${tempDir.path}/$name');
      await file.writeAsBytes(pngBytes);
      return file;
    }

    // Drain the stream so the HTTP request actually fires; assertions run on
    // the captured request afterwards.
    Future<void> drain(LlamaApiService apiService, List<ChatMessage> history) async {
      await for (final _ in apiService.streamChatCompletions(
        serverConfig: buildServerConfig(),
        connection: buildServerProfile(
          baseUrl: 'http://127.0.0.1:8080',
        ),
        history: history,
        systemPrompt: 'You are a helpful AI.',
      )) {
        // consume
      }
    }

    test('sends image as base64 image_url content part', () async {
      final imageFile = await writeImage('photo.png');

      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":null}]}\n\n'
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final httpClient = ApiHttpClient(client: mockClient);
      final apiService = LlamaApiService(httpClient, LatencyMeter(httpClient));

      await drain(apiService, [
        buildMessage(
          threadId: 't1',
          role: MessageRole.user,
          content: 'What is in this image?',
          imagePath: imageFile.path,
        ),
      ]);

      expect(capturedRequest.url.path, equals('/v1/chat/completions'));
      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      final userMsg =
          messages.firstWhere((m) => (m as Map<String, dynamic>)['role'] == 'user')
              as Map<String, dynamic>;

      // Content becomes an array of typed parts when an image is attached.
      final content = userMsg['content'] as List<dynamic>;
      expect(content, hasLength(2));
      expect(content[0], {'type': 'text', 'text': 'What is in this image?'});

      final imageUrl = (content[1] as Map<String, dynamic>)['image_url']
          as Map<String, dynamic>;
      final url = imageUrl['url'] as String;
      expect(url, startsWith('data:image/png;base64,'));
      expect(url.split(',').last, equals(base64Encode(pngBytes)));
    });

    test('sniffs the true format when the filename extension lies', () async {
      // File named .png, but the bytes are a JPEG (magic FF D8 FF).
      final mislabeledFile = File('${tempDir.path}/actually_jpeg.png');
      final jpegBytes = <int>[
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46,
      ];
      await mislabeledFile.writeAsBytes(jpegBytes);

      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":null}]}\\n\\n'
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\\n\\n'
          'data: [DONE]\\n\\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final httpClient = ApiHttpClient(client: mockClient);
      final apiService = LlamaApiService(httpClient, LatencyMeter(httpClient));

      await drain(apiService, [
        buildMessage(
          threadId: 't1',
          role: MessageRole.user,
          content: 'What is in this image?',
          imagePath: mislabeledFile.path,
        ),
      ]);

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      final userMsg =
          messages.firstWhere((m) => (m as Map<String, dynamic>)['role'] == 'user')
              as Map<String, dynamic>;
      final content = userMsg['content'] as List<dynamic>;
      final url =
          ((content[1] as Map<String, dynamic>)['image_url'] as Map<String, dynamic>)['url']
              as String;

      // Must be jpeg (from bytes), not png (from the filename).
      expect(url, startsWith('data:image/jpeg;base64,'));
      expect(url.split(',').last, equals(base64Encode(jpegBytes)));
    });

    test('keeps plain string content when message has no image', () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":null}]}\n\n'
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final httpClient = ApiHttpClient(client: mockClient);
      final apiService = LlamaApiService(httpClient, LatencyMeter(httpClient));

      await drain(apiService, [
        buildMessage(
          threadId: 't1',
          role: MessageRole.user,
          content: 'Plain text question',
        ),
      ]);

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      final userMsg =
          messages.firstWhere((m) => (m as Map<String, dynamic>)['role'] == 'user')
              as Map<String, dynamic>;
      expect(userMsg['content'], equals('Plain text question'));
    });

    test('falls back to plain text when image file is missing', () async {
      final missingPath = '${tempDir.path}/does_not_exist.png';

      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":null}]}\n\n'
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final httpClient = ApiHttpClient(client: mockClient);
      final apiService = LlamaApiService(httpClient, LatencyMeter(httpClient));

      await drain(apiService, [
        buildMessage(
          threadId: 't1',
          role: MessageRole.user,
          content: 'Still works',
          imagePath: missingPath,
        ),
      ]);

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      final userMsg =
          messages.firstWhere((m) => (m as Map<String, dynamic>)['role'] == 'user')
              as Map<String, dynamic>;
      // Broken attachment must degrade to plain text, never crash the request.
      expect(userMsg['content'], equals('Still works'));
    });
  });
}