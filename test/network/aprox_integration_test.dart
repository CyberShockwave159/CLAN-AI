import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clan_ai/core/constants/api_endpoints.dart';
import 'package:clan_ai/core/constants/aprox_capabilities.dart';
import 'package:clan_ai/core/network/http_client.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';
import 'package:clan_ai/data/datasources/aprox_rag_client.dart';
import 'package:clan_ai/data/datasources/llama_api_service.dart';
import 'package:clan_ai/data/datasources/request_options.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/test_model_factories.dart';

/// Minimal PNG header bytes. Enough for magic-byte sniffing, which is all the
/// reference-image path needs before it inlines bytes as base64.
final _pngBytes = Uint8List.fromList(
  <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4],
);

const _okSseBody =
    'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":null}]}\n\n'
    'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
    'data: [DONE]\n\n';

ServerProfile _aproxProfile({Set<String>? capabilities}) {
  return ServerProfile(
    name: 'A-PROX',
    baseUrl: 'http://127.0.0.1:8000',
    capabilities: capabilities ?? AproxCapabilities.all,
  );
}

void main() {
  group('Capability detection', () {
    test('parses the capabilities array from a /health payload', () {
      final caps = PingResult.parseCapabilities({
        'status': 'healthy',
        'service': 'A-PROX',
        'capabilities': ['rag', 'image', 'file'],
      });
      expect(caps, {'rag', 'image', 'file'});
    });

    test('normalizes case and drops malformed capability entries', () {
      final caps = PingResult.parseCapabilities({
        'capabilities': ['rag', 'IMAGE', 42, null, '  '],
      });
      // Case is normalized so a differently-cased server tag still matches;
      // non-string and blank entries are dropped rather than failing the parse,
      // because one bad entry must not cost the whole capability set.
      expect(caps, {'rag', 'image'});
    });

    test('a capabilities value of the wrong shape is ignored, not thrown on', () {
      // A newer or buggy server sending `capabilities: "rag"` (or a number)
      // must not break the health poll that every other feature depends on.
      expect(PingResult.parseCapabilities({'capabilities': 'rag'}), isEmpty);
      expect(PingResult.parseCapabilities({'capabilities': 7}), isEmpty);
    });

    test('returns empty for a llama.cpp /health payload', () {
      expect(PingResult.parseCapabilities({'status': 'ok'}), isEmpty);
      expect(PingResult.parseCapabilities('a string'), isEmpty);
      expect(PingResult.parseCapabilities(null), isEmpty);
    });

    test('server profile exposes A-PROX gates from its capabilities', () {
      final full = _aproxProfile();
      expect(full.isAprox, isTrue);
      expect(full.supportsImageGeneration, isTrue);

      final ragOnly = _aproxProfile(capabilities: {AproxCapabilities.rag});
      expect(ragOnly.isAprox, isTrue);
      expect(ragOnly.supportsImageGeneration, isFalse,
          reason: 'RAG does not imply image generation');

      final plain = ServerProfile(name: 'llama.cpp', baseUrl: 'http://127.0.0.1:8080');
      expect(plain.isAprox, isFalse);
      expect(plain.supportsImageGeneration, isFalse);
    });

    test('capabilities are not persisted with the profile', () {
      // They describe the server that is reachable now, not the profile, so a
      // stale "A-PROX" tag can never survive a restart against a different
      // server.
      final map = _aproxProfile().toMap();
      expect(map.containsKey('capabilities'), isFalse);
      expect(ServerProfile.fromMap(map).capabilities, isEmpty);
    });
  });

  group('RequestOptions', () {
    test('defaults are inert', () {
      const options = RequestOptions.none;
      expect(options.modelOverride, isNull);
      expect(options.rag, isNull);
      expect(options.extraBody, isNull);
      expect(options.roleplayMode, isFalse);
      expect(options.referenceImage, isNull);
    });

    test('serverSideRag builds the routing alias and rag object', () {
      final options = RequestOptions.serverSideRag(
        collection: 'clan_abc_def',
        topK: 4,
        minScore: 0.25,
      );
      expect(options.modelOverride, 'a-prox-rag');
      expect(options.rag, {
        'collection': 'clan_abc_def',
        'top_k': 4,
        'min_score': 0.25,
      });
      expect(options.roleplayMode, isTrue);
    });

    test('sceneImage is not marked roleplay', () {
      // /image already forces a loop with only image_generate armed; adding the
      // roleplay marker would also arm rag_search for a picture request.
      final options = RequestOptions.sceneImage(
        style: 'anime',
        referenceImage: _pngBytes,
      );
      expect(options.roleplayMode, isFalse);
      expect(options.extraBody, {'image_style': 'anime'});
      expect(options.referenceImage, _pngBytes);
    });

    test('sceneImage asks for image-only delivery', () {
      // The scene-image flow discards streamed text, so the vision caption turn
      // and the synthesis turn are pure cost — measured at ~85s on a 35B model.
      expect(RequestOptions.sceneImage().imageOnly, isTrue);
      expect(RequestOptions.none.imageOnly, isFalse);
    });

    test('sceneImage omits image_style when no theme is set', () {
      expect(RequestOptions.sceneImage().extraBody, isNull);
    });
  });

  group('GenerationParams.toOpenAiPayload A-PROX fields', () {
    test('modelOverride replaces the selected model', () {
      final payload = const GenerationParams().toOpenAiPayload(
        messages: const [],
        model: 'qwen3.6-35b-moe',
        modelOverride: 'a-prox-rag',
      );
      expect(payload['model'], 'a-prox-rag');
    });

    test('the selected model is used when there is no override', () {
      final payload = const GenerationParams().toOpenAiPayload(
        messages: const [],
        model: 'qwen3.6-35b-moe',
      );
      expect(payload['model'], 'qwen3.6-35b-moe');
    });

    test('rag and extraBody are included only when supplied', () {
      final bare = const GenerationParams().toOpenAiPayload(
        messages: const [],
        model: 'm',
      );
      expect(bare.containsKey('rag'), isFalse);
      expect(bare.containsKey('image_style'), isFalse);

      final full = const GenerationParams().toOpenAiPayload(
        messages: const [],
        model: 'm',
        rag: {'collection': 'c', 'top_k': 2},
        extraBody: {'image_style': 'anime'},
      );
      expect(full['rag'], {'collection': 'c', 'top_k': 2});
      expect(full['image_style'], 'anime');
    });
  });

  group('LlamaApiService A-PROX request fields', () {
    late Directory tempDir;
    late LlamaApiService apiService;
    late Map<String, dynamic> capturedBody;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('clan_ai_aprox_test');
      capturedBody = <String, dynamic>{};
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    /// Builds a service whose requests are captured, then drained.
    Future<void> drain({
      required List<ChatMessage> history,
      RequestOptions options = RequestOptions.none,
    }) async {
      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(_okSseBody, 200,
            headers: {'content-type': 'text/event-stream'});
      });
      apiService = LlamaApiService(
        ApiHttpClient(client: mockClient),
        LatencyMeter(ApiHttpClient(client: mockClient)),
      );
      await for (final _ in apiService.streamChatCompletions(
        serverConfig: buildServerConfig(),
        connection: _aproxProfile(),
        history: history,
        systemPrompt: 'sys',
        options: options,
      )) {
        // consume
      }
    }

    test('roleplayMode tags every message, system prompt included', () async {
      await drain(
        history: [
          buildMessage(role: MessageRole.user, content: 'hello'),
          buildMessage(role: MessageRole.assistant, content: 'hi'),
        ],
        options: const RequestOptions(roleplayMode: true),
      );
      for (final message in capturedBody['messages'] as List<dynamic>) {
        expect((message as Map)['roleplay'], isTrue,
            reason: 'message ${message['role']} must be tagged');
      }
    });

    test('messages are untagged when roleplayMode is off', () async {
      await drain(
        history: [buildMessage(role: MessageRole.user, content: 'hello')],
      );
      for (final message in capturedBody['messages'] as List<dynamic>) {
        expect((message as Map).containsKey('roleplay'), isFalse);
      }
    });

    test('a reference image becomes array content on the final user message',
        () async {
      await drain(
        history: [
          buildMessage(role: MessageRole.user, content: 'first'),
          buildMessage(role: MessageRole.assistant, content: 'reply'),
          buildMessage(role: MessageRole.user, content: '/image a garden'),
        ],
        options: RequestOptions.sceneImage(
          style: 'anime',
          referenceImage: _pngBytes,
        ),
      );

      final messages = capturedBody['messages'] as List<dynamic>;
      // Locate the last user message, which is where A-PROX looks for a
      // reference.
      final lastUser = messages
          .whereType<Map>()
          .lastWhere((m) => m['role'] == 'user');
      final content = lastUser['content'];
      expect(content, isA<List<dynamic>>(),
          reason: 'a plain string would make A-PROX ignore the reference');

      final parts = content as List<dynamic>;
      expect(parts.whereType<Map>().any((p) => p['type'] == 'text'), isTrue);
      final imagePart = parts.whereType<Map>().firstWhere(
            (p) => p['type'] == 'image_url',
          );
      final url = ((imagePart['image_url'] as Map)['url'] as String);
      expect(url, startsWith('data:image/png;base64,'));

      // The style and the image-only flag ride at the top level, not in the
      // message.
      expect(capturedBody['image_style'], 'anime');
      expect(capturedBody['image_only'], isTrue);
    });

    test('a reference is not attached to an assistant-only history', () async {
      await drain(
        history: [buildMessage(role: MessageRole.assistant, content: 'only')],
        options: RequestOptions.sceneImage(referenceImage: _pngBytes),
      );
      final messages = capturedBody['messages'] as List<dynamic>;
      for (final message in messages.whereType<Map>()) {
        if (message['role'] == 'user') {
          expect(message['content'], isA<String>(),
              reason: 'A-PROX only reads array content off a user turn');
        }
      }
    });

    test('an existing image part is not duplicated', () async {
      // A user message with a stored attachment already serializes as array
      // content; adding a reference must not append a second image_url.
      final file = File('${tempDir.path}/a.png');
      await file.writeAsBytes(_pngBytes);
      await drain(
        history: [
          buildMessage(
            role: MessageRole.user,
            content: '/image x',
            imagePath: file.path,
          ),
        ],
        options: RequestOptions.sceneImage(referenceImage: _pngBytes),
      );
      final messages = capturedBody['messages'] as List<dynamic>;
      final lastUser = messages.whereType<Map>().lastWhere((m) => m['role'] == 'user');
      final parts = lastUser['content'] as List<dynamic>;
      expect(parts.whereType<Map>().where((p) => p['type'] == 'image_url').length, 1);
    });

    test('the rag object and model alias reach the wire together', () async {
      await drain(
        history: [buildMessage(role: MessageRole.user, content: 'hi')],
        options: RequestOptions.serverSideRag(
          collection: 'clan_c1_t1',
          topK: 5,
          minScore: 0.1,
        ),
      );
      expect(capturedBody['model'], 'a-prox-rag');
      expect(capturedBody['rag'], {
        'collection': 'clan_c1_t1',
        'top_k': 5,
        'min_score': 0.1,
      });
    });
  });

  group('LlamaApiService.completeOnce', () {
    test('returns the assistant text and never streams', () async {
      late http.Request captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': 'A auburn-haired woman in a sunlit parlour.',
                }
              }
            ]
          }),
          200,
        );
      });
      final service = LlamaApiService(
        ApiHttpClient(client: mockClient),
        LatencyMeter(ApiHttpClient(client: mockClient)),
      );

      final text = await service.completeOnce(
        serverConfig: buildServerConfig(),
        connection: _aproxProfile(),
        systemPrompt: 'writer',
        messages: const [
          {'role': 'user', 'content': 'describe'},
        ],
      );

      expect(text, 'A auburn-haired woman in a sunlit parlour.');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['stream'], isFalse);
      expect(body['max_tokens'], isA<int>(),
          reason: 'an auxiliary call must be budgeted');
    });

    test("respects a caller's explicit maxTokens over the auxiliary default",
        () async {
      // Overriding a caller-chosen budget would silently ignore the user's
      // Generation Parameters for auxiliary calls only.
      late http.Request captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'ok'}
              }
            ]
          }),
          200,
        );
      });
      final service = LlamaApiService(
        ApiHttpClient(client: mockClient),
        LatencyMeter(ApiHttpClient(client: mockClient)),
      );

      await service.completeOnce(
        serverConfig: buildServerConfig(),
        connection: _aproxProfile(),
        systemPrompt: null,
        messages: const [],
        params: const GenerationParams(maxTokens: 777),
      );
      expect(jsonDecode(captured.body)['max_tokens'], 777);
    });

    test('a per-call maxTokens override wins over every default', () async {
      late http.Request captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response('{"choices":[]}', 200);
      });
      final service = LlamaApiService(
        ApiHttpClient(client: mockClient),
        LatencyMeter(ApiHttpClient(client: mockClient)),
      );
      await service.completeOnce(
        serverConfig: buildServerConfig(),
        connection: _aproxProfile(),
        systemPrompt: null,
        messages: const [],
        params: const GenerationParams(maxTokens: 128),
        maxTokens: 4096,
      );
      expect(jsonDecode(captured.body)['max_tokens'], 4096);
    });

    test('the default auxiliary budget stays tight', () async {
      // Appearance drafting and style detection want a few dozen words and must
      // not inherit the scene-draft's reasoning-sized budget.
      late http.Request captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response('{"choices":[]}', 200);
      });
      final service = LlamaApiService(
        ApiHttpClient(client: mockClient),
        LatencyMeter(ApiHttpClient(client: mockClient)),
      );
      await service.completeOnce(
        serverConfig: buildServerConfig(),
        connection: _aproxProfile(),
        systemPrompt: null,
        messages: const [],
      );
      expect(jsonDecode(captured.body)['max_tokens'], lessThan(512));
    });

    test('a per-call timeout override reaches the request', () async {
      // Regression: a reasoning call that ran past the shared 60s receive budget
      // was aborted client-side even though the server had already answered, and
      // surfaced as an empty result.
      late Duration observed;
      final mockClient = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return http.Response('{"choices":[]}', 200);
      });
      final service = LlamaApiService(
        ApiHttpClient(client: mockClient, receiveTimeout: const Duration(seconds: 60)),
        LatencyMeter(ApiHttpClient(client: mockClient)),
      );

      final stopwatch = Stopwatch()..start();
      await service.completeOnce(
        serverConfig: buildServerConfig(),
        connection: _aproxProfile(),
        systemPrompt: null,
        messages: const [],
        timeout: const Duration(seconds: 5),
      );
      stopwatch.stop();
      observed = stopwatch.elapsed;
      expect(observed, lessThan(const Duration(seconds: 5)),
          reason: 'the generous ceiling must not delay a fast response');
    });

    test('a long call is NOT killed by the default 60s receive budget', () async {
      // A 300ms stand-in for a 62s reasoning call, against a 100ms budget: with
      // the override the response arrives instead of throwing.
      final slow = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'a sunlit kitchen'}
              }
            ]
          }),
          200,
        );
      });
      final service = LlamaApiService(
        ApiHttpClient(client: slow, receiveTimeout: const Duration(milliseconds: 100)),
        LatencyMeter(ApiHttpClient(client: slow)),
      );

      // Without the override this throws a NetworkException.
      await expectLater(
        service.completeOnce(
          serverConfig: buildServerConfig(),
          connection: _aproxProfile(),
          systemPrompt: null,
          messages: const [],
        ),
        throwsA(isA<Exception>()),
      );

      // With it, the same request succeeds.
      final text = await service.completeOnce(
        serverConfig: buildServerConfig(),
        connection: _aproxProfile(),
        systemPrompt: null,
        messages: const [],
        timeout: const Duration(seconds: 5),
      );
      expect(text, 'a sunlit kitchen');
    });

    test('returns empty for a body with no choices', () async {
      final mockClient =
          MockClient((request) async => http.Response('{}', 200));
      final service = LlamaApiService(
        ApiHttpClient(client: mockClient),
        LatencyMeter(ApiHttpClient(client: mockClient)),
      );
      expect(
        await service.completeOnce(
          serverConfig: buildServerConfig(),
          connection: _aproxProfile(),
          systemPrompt: null,
          messages: const [],
        ),
        isEmpty,
      );
    });
  });

  group('AproxRagClient', () {
    test('collection names scope memories per character and thread', () {
      // A-PROX searches every collection when no filter is given, so a shared
      // namespace would leak one character's memories into another's roleplay.
      expect(
        AproxRagClient.threadCollection(characterId: 'c1', threadId: 't1'),
        'clan_c1_t1',
      );
      expect(
        AproxRagClient.threadCollection(characterId: 'c1', threadId: 't2'),
        'clan_c1_t2',
        reason: 'threads must not share a namespace',
      );
      expect(AproxRagClient.visualCollection('c1'), 'clan_c1_visual');
    });

    test('turn source uris are unique per message but stable per turn', () {
      final a = AproxRagClient.turnSourceUri(
        characterId: 'c1',
        threadId: 't1',
        messageId: 'm1',
      );
      final b = AproxRagClient.turnSourceUri(
        characterId: 'c1',
        threadId: 't1',
        messageId: 'm1',
      );
      final c = AproxRagClient.turnSourceUri(
        characterId: 'c1',
        threadId: 't1',
        messageId: 'm2',
      );
      expect(a, b, reason: 're-ingesting a turn must replace, not duplicate');
      expect(a, isNot(c));
    });

    test('the visual source uri is stable so the sheet is replaced', () {
      expect(
        AproxRagClient.visualSourceUri('c1'),
        AproxRagClient.visualSourceUri('c1'),
      );
      expect(
        AproxRagClient.visualSourceUri('c1'),
        isNot(AproxRagClient.visualSourceUri('c2')),
      );
    });

    test('ingest posts to /rag/ingest with the collection and source', () async {
      late http.Request captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'status': 'ok', 'chunks': 2}), 200);
      });
      final client = AproxRagClient(ApiHttpClient(client: mockClient));

      final chunks = await client.ingest(
        connection: _aproxProfile(),
        collection: 'clan_c1_t1',
        sourceUri: 'clan/c1/t1/m1',
        content: 'User: hi\nAlice: hello',
      );

      expect(chunks, 2);
      expect(captured.url.path, ApiEndpoints.ragIngest);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['collection'], 'clan_c1_t1');
      expect(body['source_uri'], 'clan/c1/t1/m1');
      expect(body['content'], 'User: hi\nAlice: hello');
    });

    test('ingest refuses empty content without a request', () async {
      var called = false;
      final mockClient = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });
      final client = AproxRagClient(ApiHttpClient(client: mockClient));
      expect(
        await client.ingest(
          connection: _aproxProfile(),
          collection: 'c',
          sourceUri: 's',
          content: '   ',
        ),
        isNull,
      );
      expect(called, isFalse);
    });

    test('query omits the collection key when no filter is given', () async {
      late http.Request captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'status': 'ok', 'results': []}), 200);
      });
      final client = AproxRagClient(ApiHttpClient(client: mockClient));

      await client.query(connection: _aproxProfile(), query: 'what did we agree');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(captured.url.path, ApiEndpoints.ragQuery);
      expect(body.containsKey('collection'), isFalse);

      await client.query(
        connection: _aproxProfile(),
        query: 'x',
        collection: 'clan_c1_visual',
      );
      final scoped = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(scoped['collection'], 'clan_c1_visual');
    });

    test('query parses hits including the score', () async {
      final mockClient = MockClient((request) async => http.Response(
            jsonEncode({
              'status': 'ok',
              'results': [
                {
                  'chunk_id': 7,
                  'collection': 'clan_c1_visual',
                  'source_uri': 'clan/c1/visual',
                  'chunk_index': 0,
                  'content': 'Auburn hair, green eyes',
                  'score': 0.81,
                }
              ]
            }),
            200,
          ));
      final client = AproxRagClient(ApiHttpClient(client: mockClient));
      final hits = await client.query(
        connection: _aproxProfile(),
        query: 'eyes',
        collection: 'clan_c1_visual',
      );
      expect(hits, hasLength(1));
      expect(hits!.single.content, 'Auburn hair, green eyes');
      expect(hits.single.score, closeTo(0.81, 1e-9));
      expect(hits.single.sourceUri, 'clan/c1/visual');
    });

    test('collectionCount hits the per-collection count route', () async {
      late http.Request captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
            jsonEncode({'status': 'ok', 'chunks': 12, 'chunks_total': 40}),
            200);
      });
      final client = AproxRagClient(ApiHttpClient(client: mockClient));
      final count = await client.collectionCount(
        connection: _aproxProfile(),
        collection: 'clan_c1_t1',
      );
      expect(count, 12);
      expect(captured.url.path, '/rag/collections/clan_c1_t1/count');
    });

    test('failures are swallowed — memory is best-effort', () async {
      final mockClient = MockClient((request) async => throw const SocketException('down'));
      final client = AproxRagClient(ApiHttpClient(client: mockClient));
      final profile = _aproxProfile();

      expect(
        await client.ingest(
          connection: profile,
          collection: 'c',
          sourceUri: 's',
          content: 'text',
        ),
        isNull,
      );
      expect(await client.query(connection: profile, query: 'q'), isNull);
      expect(await client.collectionCount(connection: profile, collection: 'c'), 0);
    });

    test('an absent connection short-circuits every call', () async {
      var called = false;
      final mockClient = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });
      final client = AproxRagClient(ApiHttpClient(client: mockClient));
      expect(
        await client.ingest(
          connection: null,
          collection: 'c',
          sourceUri: 's',
          content: 'text',
        ),
        isNull,
      );
      expect(await client.query(connection: null, query: 'q'), isNull);
      expect(await client.collectionCount(connection: null, collection: 'c'), 0);
      expect(called, isFalse);
    });

    test('isAvailable requires the A-PROX RAG capability', () {
      expect(AproxRagClient.isAvailable(_aproxProfile()), isTrue);
      expect(
        AproxRagClient.isAvailable(
          ServerProfile(name: 'llama.cpp', baseUrl: 'http://127.0.0.1:8080'),
        ),
        isFalse,
      );
      expect(AproxRagClient.isAvailable(null), isFalse);
    });
  });

  group('VisualTheme', () {
    test('maps to the A-PROX styles-table keys', () {
      expect(VisualTheme.anime.wireValue, 'anime');
      expect(VisualTheme.semiRealistic.wireValue, 'semi-realistic');
      expect(VisualTheme.photoRealistic.wireValue, 'photo-realistic');
    });

    test('none is unset and sends no directive', () {
      expect(VisualTheme.none.wireValue, isNull);
      expect(VisualTheme.none.isSet, isFalse);
      expect(RequestOptions.sceneImage(style: VisualTheme.none.wireValue)
          .extraBody, isNull);
    });

    test('parses a wire value case-insensitively', () {
      expect(VisualTheme.fromWire('ANIME'), VisualTheme.anime);
      expect(VisualTheme.fromWire(' semi-realistic '), VisualTheme.semiRealistic);
    });

    test('an unknown or missing wire value degrades to none', () {
      // A server with a styles table this build doesn't know about must not
      // crash character loading.
      expect(VisualTheme.fromWire('watercolour'), VisualTheme.none);
      expect(VisualTheme.fromWire(null), VisualTheme.none);
    });
  });

  group('Reference image format handling', () {
    test('the three formats A-PROX accepts are all sniffed', () {
      expect(
        MessageAttachmentStore.mimeTypeFromBytes(
          Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0]),
        ),
        'image/jpeg',
      );
      expect(
        MessageAttachmentStore.mimeTypeFromBytes(
          Uint8List.fromList(
              <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ),
        'image/png',
      );
      expect(
        MessageAttachmentStore.mimeTypeFromBytes(
          Uint8List.fromList(<int>[
            0x52, 0x49, 0x46, 0x46, // "RIFF"
            0x1A, 0x00, 0x00, 0x00, // chunk size
            0x57, 0x45, 0x42, 0x50, // "WEBP"
          ]),
        ),
        'image/webp',
        reason: 'WebP is one of the three formats A-PROX accepts as a reference',
      );
    });

    test('the reference endpoint is not the artifact endpoint', () {
      // Guards against a copy/paste slip that would send memory writes to the
      // image server path.
      expect(ApiEndpoints.ragIngest, '/rag/ingest');
      expect(ApiEndpoints.ragQuery, '/rag/query');
      expect(ApiEndpoints.ragCollectionCount, '/rag/collections');
    });
  });
}
