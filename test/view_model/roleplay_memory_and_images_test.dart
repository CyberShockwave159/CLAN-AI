import 'package:clan_ai/core/constants/aprox_capabilities.dart';
import 'package:clan_ai/core/utils/identity_reference.dart';
import 'dart:typed_data';

import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/ui/features/roleplay/services/character_image_assist.dart';
import 'package:clan_ai/ui/features/roleplay/services/scene_image_generator.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/roleplay_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_chat_repository.dart';
import '../helpers/fake_character_repository.dart';
import '../helpers/fake_vector_store.dart';
import '../helpers/mock_path_provider.dart';
import '../helpers/test_model_factories.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late FakeChatRepository chatRepo;
  late FakeCharacterRepository charRepo;
  late RoleplayViewModel vm;
  late ServerConfig serverConfig;
  late ServerProfile plainConnection;
  late ServerProfile aproxConnection;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    setupMockPathProvider();
    chatRepo = FakeChatRepository();
    charRepo = FakeCharacterRepository();
    serverConfig = const ServerConfig();
    plainConnection =
        ServerProfile(name: 'llama.cpp', baseUrl: 'http://127.0.0.1:8080');
    aproxConnection = ServerProfile(
      name: 'A-PROX',
      baseUrl: 'http://127.0.0.1:8000',
      capabilities: AproxCapabilities.all,
    );
    vm = RoleplayViewModel(chatRepo, charRepo);
    await Future.delayed(const Duration(milliseconds: 200));
  });

  tearDown(() => vm.dispose());

  /// Puts [vm] into an active roleplay with [turns] user/assistant pairs.
  Future<void> startWithTurns(int turns) async {
    final character = buildCharacter(name: 'Alice', id: 'char-1');
    await charRepo.createCharacter(character);
    final thread = await chatRepo.createThread(
      title: 'Chat',
      characterId: 'char-1',
    );
    vm.activeThread = thread;
    vm.activeCharacter = character;
    vm.messages = <ChatMessage>[];
    for (var i = 0; i < turns; i++) {
      vm.messages.addAll([
        buildMessage(
          threadId: thread.id,
          role: MessageRole.user,
          content: 'user turn $i',
        ),
        buildMessage(
          threadId: thread.id,
          role: MessageRole.assistant,
          content: 'Alice replies $i',
        ),
      ]);
    }
  }

  group('Memory backend selection', () {
    test('is off by default', () {
      expect(
        vm.isServerRagActive(
          serverConfig: serverConfig,
          connection: aproxConnection,
        ),
        isFalse,
      );
    });

    test('requires both the setting and an A-PROX server', () {
      final enabled = serverConfig.copyWith(serverSideRagEnabled: true);
      expect(
        vm.isServerRagActive(
          serverConfig: enabled,
          connection: aproxConnection,
        ),
        isTrue,
      );
      // The setting alone is not enough: against llama.cpp an `a-prox-rag`
      // model alias would be rejected, so roleplay must keep local RAG.
      expect(
        vm.isServerRagActive(
          serverConfig: enabled,
          connection: plainConnection,
        ),
        isFalse,
      );
    });

    test('a null connection never activates server RAG', () {
      final enabled = serverConfig.copyWith(serverSideRagEnabled: true);
      expect(
        vm.isServerRagActive(serverConfig: enabled, connection: null),
        isFalse,
      );
    });
  });

  group('Server RAG does not touch the client pipeline', () {
    test('a server-RAG turn embeds nothing locally', () async {
      final fakeVectorStore = FakeVectorStore();
      final character = buildCharacter(name: 'Alice', id: 'char-1');
      await charRepo.createCharacter(character);
      final thread =
          await chatRepo.createThread(title: 'T', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = <ChatMessage>[];

      // FakeVectorStore is the injected store for the local path; with server
      // RAG on it must stay empty.
      final count = await fakeVectorStore.getEmbeddingCount('char-1');
      expect(count, 0);
    });

    test('server RAG produces no local memory metadata on the message', () async {
      await startWithTurns(1);
      final enabled = serverConfig.copyWith(serverSideRagEnabled: true);

      // sendMessage stamps ragMemoryCount/Contents from the *local* retrieval.
      // On the server backend those must stay null so the bubble hides the
      // memory chip — A-PROX injects its own context at request time.
      await vm.sendMessage(
        prompt: 'hello again',
        serverConfig: enabled,
        connection: aproxConnection,
      );

      final assistant = vm.messages.lastWhere(
        (m) => m.role == MessageRole.assistant,
      );
      expect(assistant.ragMemoryCount, isNull);
      expect(assistant.ragMemoryContents, isNull);
    });
  });

  group('RequestOptions produced for a roleplay turn', () {
    test('client RAG sends no A-PROX fields at all', () async {
      await startWithTurns(0);
      await vm.sendMessage(
        prompt: 'hello',
        serverConfig: serverConfig,
        connection: aproxConnection,
      );
      final options = chatRepo.lastStreamOptions;
      expect(options, isNotNull);
      expect(options!.modelOverride, isNull);
      expect(options.rag, isNull);
      expect(options.roleplayMode, isFalse);
      expect(options.extraBody, isNull);
    });

    test('server RAG sends the alias, the rag object and the roleplay marker',
        () async {
      await startWithTurns(0);
      final enabled = serverConfig.copyWith(
        serverSideRagEnabled: true,
        defaultParams: serverConfig.defaultParams.copyWith(
          ragTopK: 4,
          ragMinScore: 0.3,
        ),
      );
      await vm.sendMessage(
        prompt: 'hello',
        serverConfig: enabled,
        connection: aproxConnection,
      );

      final options = chatRepo.lastStreamOptions!;
      expect(options.modelOverride, 'a-prox-rag');
      expect(options.roleplayMode, isTrue);
      final rag = options.rag!;
      expect(rag['collection'], isNotNull);
      expect(rag['collection'], contains('char-1'));
      expect(rag['top_k'], 4);
      expect(rag['min_score'], closeTo(0.3, 1e-9));
    });

    test('the enabled setting is inert against a non-A-PROX server', () async {
      await startWithTurns(0);
      final enabled = serverConfig.copyWith(serverSideRagEnabled: true);
      await vm.sendMessage(
        prompt: 'hello',
        serverConfig: enabled,
        connection: plainConnection,
      );
      expect(chatRepo.lastStreamOptions!.modelOverride, isNull);
    });
  });

  group('SceneImagePrompts.buildSceneHistory', () {
    test('appends a synthetic /image turn to the last few messages', () {
      final messages = <ChatMessage>[
        for (var i = 0; i < 3; i++) ...[
          buildMessage(role: MessageRole.user, content: 'u$i'),
          buildMessage(role: MessageRole.assistant, content: 'a$i'),
        ],
      ];
      final history = SceneImagePrompts.buildSceneHistory(
        messages: messages,
        targetIndex: 5,
        imagePrompt: 'a woman in a garden',
      );
      expect(history.last.role, MessageRole.user);
      expect(history.last.content, '/image a woman in a garden');
      // The target assistant message is the last real turn, so the enhancer sees
      // the scene it is being asked to illustrate.
      expect(history[history.length - 2].content, 'a2');
    });

    test('keeps at most the configured window', () {
      final messages = <ChatMessage>[
        for (var i = 0; i < 20; i++)
          buildMessage(
            role: i.isEven ? MessageRole.user : MessageRole.assistant,
            content: 'm$i',
          ),
      ];
      final history = SceneImagePrompts.buildSceneHistory(
        messages: messages,
        targetIndex: 19,
        imagePrompt: 'p',
      );
      // window + the synthetic command turn
      expect(
        history.length,
        SceneImagePrompts.sceneContextMessageCount + 1,
      );
      expect(history.last.content, '/image p');
    });

    test('drops streaming and empty messages from the context', () {
      final messages = <ChatMessage>[
        buildMessage(role: MessageRole.user, content: 'kept'),
        buildMessage(
          role: MessageRole.assistant,
          content: '',
          status: MessageStatus.completed,
        ),
        buildMessage(
          role: MessageRole.assistant,
          content: 'still streaming',
          status: MessageStatus.streaming,
        ),
        buildMessage(role: MessageRole.assistant, content: 'target'),
      ];
      final history = SceneImagePrompts.buildSceneHistory(
        messages: messages,
        targetIndex: 3,
        imagePrompt: 'p',
      );
      expect(
        history.where((m) => m.content == 'still streaming'),
        isEmpty,
      );
      expect(history.where((m) => m.content.isEmpty), isEmpty);
      expect(history.map((m) => m.content), contains('kept'));
    });

    test('handles a target index near the start of the thread', () {
      final messages = <ChatMessage>[
        buildMessage(role: MessageRole.assistant, content: 'greeting'),
      ];
      final history = SceneImagePrompts.buildSceneHistory(
        messages: messages,
        targetIndex: 0,
        imagePrompt: 'p',
      );
      expect(history.map((m) => m.content), ['greeting', '/image p']);
    });
  });

  group('SceneImagePrompts.imageCommand', () {
    test('asks for a new scene rather than an edit', () {
      // The enhancer's system prompt treats every request as an image edit, so
      // without this framing it would preserve the reference portrait's pose and
      // background instead of placing the character in the scene.
      final command = SceneImagePrompts.imageCommand(
        characterName: 'Sarah',
        draftedPrompt: 'Sarah holds a parcel in a snowy lane.',
      );
      expect(command.toLowerCase(), contains('new picture'));
      expect(command.toLowerCase(), contains('not an edit'));
      expect(command, contains('Sarah holds a parcel'));
    });

    test('pins the appearance traits when a sheet exists', () {
      final command = SceneImagePrompts.imageCommand(
        characterName: 'Sarah',
        draftedPrompt: 'a lane',
        appearance: 'Auburn hair, green eyes',
      );
      expect(command, contains('Keep these appearance traits exactly'));
      expect(command, contains('Auburn hair, green eyes'));
    });

    test('omits the appearance clause when there is no sheet', () {
      final command = SceneImagePrompts.imageCommand(
        characterName: 'Sarah',
        draftedPrompt: 'a lane',
        appearance: '   ',
      );
      expect(command.toLowerCase(), isNot(contains('appearance traits')));
    });

    test('mentions the theme only when one is set', () {
      final unset = SceneImagePrompts.imageCommand(
        characterName: 'S',
        draftedPrompt: 'p',
      );
      expect(unset.toLowerCase(), isNot(contains('style')));

      final anime = SceneImagePrompts.imageCommand(
        characterName: 'S',
        draftedPrompt: 'p',
        theme: VisualTheme.anime,
      );
      expect(anime, contains('anime'));
    });
  });

  group('SceneImagePrompts /bypass guard', () {
    test('the prompt-writer instruction is prefixed with /bypass', () {
      // Without it, a drafted prompt containing "draw"/"picture" would trip
      // A-PROX's image classifier and silently burn a second generation.
      expect(SceneImagePrompts.promptWriterInstruction, startsWith('/bypass '));
    });

    test('the appearance and style calls are also bypassed', () {
      expect(SceneImagePrompts.appearanceWriterInstruction,
          startsWith('/bypass '));
      expect(SceneImagePrompts.styleDetectorInstruction, startsWith('/bypass '));
    });
  });

  group('Scene image generation guards', () {
    test('is refused when the server cannot generate images', () async {
      await startWithTurns(1);
      final result = await vm.generateImageForMessage(
        messageIndex: 1,
        serverConfig: serverConfig,
        connection: plainConnection,
      );
      expect(result.outcome, SceneImageOutcome.unsupported);
      expect(result.isSuccess, isFalse);
    });

    test('is refused for a user message', () async {
      await startWithTurns(1);
      final result = await vm.generateImageForMessage(
        messageIndex: 0,
        serverConfig: serverConfig,
        connection: aproxConnection,
      );
      expect(result.outcome, SceneImageOutcome.failed);
    });

    test('is refused for an out-of-range index', () async {
      await startWithTurns(1);
      final result = await vm.generateImageForMessage(
        messageIndex: 99,
        serverConfig: serverConfig,
        connection: aproxConnection,
      );
      expect(result.outcome, SceneImageOutcome.failed);
    });

    test('a second tap during the prompt draft is refused', () async {
      // Step 1 runs before streaming starts, so isGenerating is still false
      // during it — without a dedicated guard a double tap would run two
      // drafts and create two variants.
      await startWithTurns(1);
      final first = vm.generateImageForMessage(
        messageIndex: 1,
        serverConfig: serverConfig,
        connection: aproxConnection,
      );
      // Second call lands while the first is still awaiting its draft.
      final second = await vm.generateImageForMessage(
        messageIndex: 1,
        serverConfig: serverConfig,
        connection: aproxConnection,
      );
      expect(second.outcome, SceneImageOutcome.busy);
      await first;
      // Whatever the outcome, no duplicate variant may be left behind.
      expect(vm.messages, hasLength(2));
    });

    test('fails cleanly when the prompt draft cannot be produced', () async {
      await startWithTurns(1);
      // No canned response configured, so completeOnce returns ''.
      final result = await vm.generateImageForMessage(
        messageIndex: 1,
        serverConfig: serverConfig,
        connection: aproxConnection,
      );
      expect(result.outcome, SceneImageOutcome.failed);
      // Crucially, no variant was left behind for a request that never ran.
      expect(vm.messages, hasLength(2));
    });
  });

  group('Identity reference resolution', () {
    test('an approved portrait wins over the card avatar', () {
      final character = buildCharacter(name: 'S', id: 'c1').copyWith(
        avatarData: _pngBytes,
        identityPortraitData: _jpegBytes,
      );
      final reference = IdentityReferenceResolver.forCharacter(character);
      expect(reference, isNotNull);
      expect(reference!.source, IdentityReferenceSource.approvedPortrait);
    });

    test('falls back to the card avatar', () {
      final character = buildCharacter(name: 'S', id: 'c1').copyWith(
        avatarData: _pngBytes,
      );
      final reference = IdentityReferenceResolver.forCharacter(character)!;
      expect(reference.source, IdentityReferenceSource.characterAvatar);
    });

    test('returns null when the character has neither', () {
      final character = buildCharacter(name: 'S', id: 'c1');
      expect(IdentityReferenceResolver.forCharacter(character), isNull);
      expect(character.needsIdentityPortrait, isTrue);
      expect(character.hasIdentityReference, isFalse);
    });

    test('empty blobs count as absent', () {
      final character = buildCharacter(name: 'S', id: 'c1').copyWith(
        avatarData: Uint8List(0),
        identityPortraitData: Uint8List(0),
      );
      expect(IdentityReferenceResolver.forCharacter(character), isNull);
    });

    test('a prior generation is labelled as such', () {
      final reference =
          IdentityReferenceResolver.fromPriorGeneration(_jpegBytes);
      expect(reference.source, IdentityReferenceSource.priorGeneration);
    });

    test('needsIdentityPortrait is false once any reference exists', () {
      final withAvatar =
          buildCharacter(name: 'S', id: 'c1').copyWith(avatarData: _pngBytes);
      expect(withAvatar.needsIdentityPortrait, isFalse);
    });

    test('an already-acceptable format is passed through untouched', () {
      // A supported, small JPEG needs no re-encode: the original bytes are
      // what the user picked, and re-encoding would only add generation loss.
      final normalized =
          IdentityReferenceResolver.normalizeForReference(_jpegBytes);
      expect(normalized, _jpegBytes);
    });

    test('undecodable bytes degrade to the original rather than failing', () {
      // A corrupt or truncated reference must not break the request; it just
      // falls back to text-to-image, which A-PROX does silently.
      final garbage = Uint8List.fromList(List<int>.filled(64, 0x7F));
      expect(
        IdentityReferenceResolver.normalizeForReference(garbage),
        garbage,
      );
    });

    test('isSupportedFormat reflects what A-PROX will accept', () {
      expect(IdentityReferenceResolver.isSupportedFormat(_jpegBytes), isTrue);
      expect(IdentityReferenceResolver.isSupportedFormat(_pngBytes), isTrue);
      expect(
        IdentityReferenceResolver.isSupportedFormat(
          Uint8List.fromList(List<int>.filled(16, 0)),
        ),
        isFalse,
        reason: 'A-PROX would silently ignore this and do text-to-image',
      );
    });
  });

  group('PortraitPrompt', () {
    test('describes a portrait, not a scene', () {
      final prompt = PortraitPrompt.build(
        characterName: 'Sarah',
        theme: VisualTheme.photoRealistic,
      );
      expect(prompt.toLowerCase(), contains('head-and-shoulders'));
      expect(prompt.toLowerCase(), contains('portrait'));
      expect(prompt, contains('Sarah'));
    });

    test('carries the theme style phrase', () {
      expect(
        PortraitPrompt.stylePhrase(VisualTheme.anime),
        contains('anime'),
      );
      expect(
        PortraitPrompt.stylePhrase(VisualTheme.semiRealistic),
        contains('semi-realistic'),
      );
    });

    test('includes the appearance sheet when present', () {
      final prompt = PortraitPrompt.build(
        characterName: 'Sarah',
        theme: VisualTheme.none,
        appearance: 'Auburn hair, green eyes',
      );
      expect(prompt, contains('Auburn hair, green eyes'));
    });
  });

  group('Scene image prompt drafting', () {
    test('the draft asks for the reasoning channel', () async {
      // With reasoning off, a reasoning model narrates a "Here's a thinking
      // process" preamble into `content`, which then shares the token budget
      // with the prompt itself and gets truncated mid-sentence.
      await startWithTurns(1);
      chatRepo.nextCompletionResponse = 'a quiet parlour, candlelight';
      await vm.generateImageForMessage(
        messageIndex: 1,
        serverConfig: serverConfig,
        connection: aproxConnection,
      );
      expect(chatRepo.lastCompleteOnceReasoning, isTrue,
          reason: 'the preamble belongs in reasoning_content, not content');
    });

    test('the draft budget clears a reasoning preamble plus the prompt', () async {
      await startWithTurns(1);
      chatRepo.nextCompletionResponse = 'a quiet parlour, candlelight';
      await vm.generateImageForMessage(
        messageIndex: 1,
        serverConfig: serverConfig,
        connection: aproxConnection,
      );
      final budget = chatRepo.lastCompleteOnceMaxTokens!;
      // Must clear the 2048 that silently produced no image, and the 1024 that
      // truncated the instruction mid-sentence.
      expect(budget, greaterThanOrEqualTo(2048));
    });

    test('the draft raises the receive timeout past the shared 60s budget', () async {
      // Regression: the draft took 62s and the default 60s `post` budget aborted
      // a response the server had already produced, reported as an empty result.
      await startWithTurns(1);
      chatRepo.nextCompletionResponse = 'a quiet parlour, candlelight';
      await vm.generateImageForMessage(
        messageIndex: 1,
        serverConfig: serverConfig,
        connection: aproxConnection,
      );
      final timeout = chatRepo.lastCompleteOnceTimeout;
      expect(timeout, isNotNull);
      expect(timeout!,
          greaterThan(const Duration(seconds: 60)),
          reason: 'reasoning at 35B routinely outlives the shared budget');
    });

    test('the draft budget leaves room to observe real usage', () async {
      await startWithTurns(1);
      chatRepo.nextCompletionResponse = 'a quiet parlour, candlelight';
      await vm.generateImageForMessage(
        messageIndex: 1,
        serverConfig: serverConfig,
        connection: aproxConnection,
      );
      expect(chatRepo.lastCompleteOnceMaxTokens,
          greaterThanOrEqualTo(16384));
    });

    test('the draft system prompt asks for deliberation then the prompt', () async {
      expect(SceneImagePrompts.promptWriterSystemPrompt,
          contains('Think through the scene first'));
      expect(SceneImagePrompts.promptWriterSystemPrompt,
          contains('only thing in your final answer'));
    });
  });

  group('CharacterImageAssist', () {
    test('refuses to draft from a thin card', () {
      // Below the threshold the "card" is a name and a line, and the model
      // would invent physical traits the user never specified.
      final thin = buildCharacter(name: 'S', id: 'c1', personality: 'grumpy');
      expect(CharacterImageAssist.canDraftAppearance(thin), isFalse);
    });

    test('offers a draft for a rich card with no sheet', () {
      final rich = buildCharacter(
        name: 'S',
        id: 'c1',
        personality: 'x' * 250,
      );
      expect(CharacterImageAssist.canDraftAppearance(rich), isTrue);
    });

    test('does not re-draft when a sheet already exists', () {
      final rich = buildCharacter(
        name: 'S',
        id: 'c1',
        personality: 'x' * 250,
      ).copyWith(appearance: 'Auburn hair');
      expect(CharacterImageAssist.canDraftAppearance(rich), isFalse);
    });

    test('draft returns null for the NONE sentinel', () async {
      chatRepo.nextCompletionResponse = 'NONE';
      final character = buildCharacter(
        name: 'S',
        id: 'c1',
        personality: 'x' * 250,
      );
      final draft = await CharacterImageAssist.draftAppearance(
        chatRepository: chatRepo,
        serverConfig: serverConfig,
        connection: aproxConnection,
        character: character,
      );
      expect(draft, isNull,
          reason: 'inventing traits is worse than having no sheet');
    });

    test('draft strips a stray label and bullet formatting', () async {
      chatRepo.nextCompletionResponse =
          'Appearance: green eyes\n- Auburn shoulder-length hair';
      final character = buildCharacter(
        name: 'S',
        id: 'c1',
        personality: 'x' * 250,
      );
      final draft = await CharacterImageAssist.draftAppearance(
        chatRepository: chatRepo,
        serverConfig: serverConfig,
        connection: aproxConnection,
        character: character,
      );
      expect(draft, 'green eyes\nAuburn shoulder-length hair');
    });

    test('the appearance call is not marked roleplay', () async {
      await CharacterImageAssist.draftAppearance(
        chatRepository: chatRepo,
        serverConfig: serverConfig,
        connection: aproxConnection,
        character: buildCharacter(
          name: 'S',
          id: 'c1',
          personality: 'x' * 250,
        ),
      );
      expect(chatRepo.lastCompleteOnceOptions?.roleplayMode, isFalse);
    });

    test('style detection parses each theme', () async {
      chatRepo.nextCompletionResponse = 'anime';
      expect(
        await CharacterImageAssist.detectVisualStyle(
          chatRepository: chatRepo,
          serverConfig: serverConfig,
          connection: aproxConnection,
          avatarBytes: _pngBytes,
        ),
        VisualTheme.anime,
      );

      chatRepo.nextCompletionResponse = 'Semi-realistic';
      expect(
        await CharacterImageAssist.detectVisualStyle(
          chatRepository: chatRepo,
          serverConfig: serverConfig,
          connection: aproxConnection,
          avatarBytes: _pngBytes,
        ),
        VisualTheme.semiRealistic,
      );
    });

    test('style detection does not confuse photo-realistic with semi', () async {
      chatRepo.nextCompletionResponse = 'photo-realistic';
      expect(
        await CharacterImageAssist.detectVisualStyle(
          chatRepository: chatRepo,
          serverConfig: serverConfig,
          connection: aproxConnection,
          avatarBytes: _pngBytes,
        ),
        VisualTheme.photoRealistic,
      );
    });

    test('style detection returns null for an unusable reply', () async {
      chatRepo.nextCompletionResponse = 'I am not sure, sorry!';
      expect(
        await CharacterImageAssist.detectVisualStyle(
          chatRepository: chatRepo,
          serverConfig: serverConfig,
          connection: aproxConnection,
          avatarBytes: _pngBytes,
        ),
        isNull,
      );
    });

    test('style detection needs an avatar', () async {
      expect(
        await CharacterImageAssist.detectVisualStyle(
          chatRepository: chatRepo,
          serverConfig: serverConfig,
          connection: aproxConnection,
          avatarBytes: Uint8List(0),
        ),
        isNull,
      );
    });
  });

}

/// Minimal PNG header bytes — enough for magic-byte sniffing.
final _pngBytes =
    Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
final _jpegBytes = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
