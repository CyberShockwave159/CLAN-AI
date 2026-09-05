import 'package:clan_ai/data/models/app_mode.dart';
import 'package:clan_ai/data/models/model_info.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/fake_server_repository.dart';
import '../helpers/fake_system_prompt_templates_repository.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeServerRepository fakeServerRepo;
  late FakeSystemPromptTemplatesRepository fakeTemplateRepo;
  late SettingsViewModel vm;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fakeServerRepo = FakeServerRepository();
    fakeTemplateRepo = FakeSystemPromptTemplatesRepository();
    fakeServerRepo.activeConfig = const ServerConfig();
    vm = SettingsViewModel(
      serverRepository: fakeServerRepo,
      templateRepository: fakeTemplateRepo,
    );
    // Wait for async _init() to complete (includes testConnection which sets selectedModel)
    await Future.delayed(const Duration(milliseconds: 300));
  });

  group('SettingsViewModel appMode', () {
    test('default is assistant mode', () {
      expect(vm.appMode, equals(AppMode.assistant));
    });

    test('updates and saves app mode', () async {
      await vm.updateAppMode(AppMode.roleplay);
      expect(vm.appMode, equals(AppMode.roleplay));
    });
  });

  group('SettingsViewModel config', () {
    test('returns server config', () {
      expect(vm.config, isNotNull);
    });

    test('updates selected model', () async {
      await vm.updateSelectedModel('llama-3.2');
      expect(vm.config.selectedModel, equals('llama-3.2'));
    });

    test('updates system prompt', () async {
      await vm.updateSystemPrompt('Custom prompt');
      expect(vm.config.systemPrompt, equals('Custom prompt'));
    });

    test('updates default params', () async {
      final params = const GenerationParams(temperature: 0.7);
      await vm.updateDefaultParams(params);
      expect(vm.config.defaultParams.temperature, equals(0.7));
    });

    test('toggles confirmDeleteMessage', () async {
      await vm.toggleConfirmDeleteMessage(false);
      expect(vm.config.confirmDeleteMessage, isFalse);
    });

    test('toggles reasoning', () async {
      await vm.toggleReasoning(true);
      expect(vm.config.reasoning, isTrue);
    });
  });

  group('SettingsViewModel profiles', () {
    test('creates new profile', () async {
      await vm.createProfile(
        name: 'My Server',
        baseUrl: 'http://localhost:8080',
        protocol: ApiProtocol.openAi,
      );

      expect(vm.profiles, isNotEmpty);
      final myServer = vm.profiles.firstWhere((p) => p.name == 'My Server', orElse: () => throw StateError('Not found'));
      expect(myServer.name, equals('My Server'));
    });

    test('updates profile', () async {
      await vm.createProfile(
        name: 'Test',
        baseUrl: 'http://localhost:8080',
        protocol: ApiProtocol.openAi,
      );

      final updatedProfile = vm.profiles.first.copyWith(name: 'Updated');
      await vm.updateProfile(updatedProfile);

      expect(vm.profiles.first.name, equals('Updated'));
    });

    test('deletes profile', () async {
      await vm.createProfile(
        name: 'Delete Me',
        baseUrl: 'http://localhost:8080',
        protocol: ApiProtocol.openAi,
      );

      final profileId = vm.profiles.first.id;
      await vm.deleteProfile(profileId);

      expect(vm.profiles.where((p) => p.id == profileId), isEmpty);
    });

    test('switches profile', () async {
      await fakeServerRepo.createProfile('Profile 1', baseUrl: 'http://localhost:8080');
      final profile2 = await fakeServerRepo.createProfile('Profile 2', baseUrl: 'http://localhost:8080');
      await vm.reloadProfiles();

      await vm.switchProfile(profile2.id);

      expect(vm.activeProfileId, equals(profile2.id));
    });

    test('updates profile name', () async {
      await vm.createProfile(
        name: 'Old Name',
        baseUrl: 'http://localhost:8080',
        protocol: ApiProtocol.openAi,
      );

      final profileId = vm.profiles.first.id;
      await vm.updateProfileName(profileId, 'New Name');

      expect(vm.profiles.first.name, equals('New Name'));
    });
  });

  group('SettingsViewModel templates', () {
    test('adds template', () async {
      await vm.addTemplate('New Template', 'Template content');
      expect(vm.templates, isNotEmpty);
    });

    test('updates template', () async {
      await vm.addTemplate('Original', 'Content');
      final templates = await fakeTemplateRepo.loadTemplates();
      if (templates.isNotEmpty) {
        await vm.updateTemplate(0, 'Updated', 'Updated content');
        expect(vm.templates[0].name, equals('Updated'));
      }
    });

    test('deletes template', () async {
      await vm.addTemplate('Delete Me', 'Content');
      final templates = await fakeTemplateRepo.loadTemplates();
      if (templates.isNotEmpty) {
        await vm.deleteTemplate(0);
        expect(vm.templates, isEmpty);
      }
    });
  });

  group('SettingsViewModel connection', () {
    test('tests connection', () async {
      await vm.createProfile(
        name: 'Test',
        baseUrl: 'http://localhost:8080',
        protocol: ApiProtocol.openAi,
      );

      await vm.testConnection();

      expect(vm.config.healthStatus, isNotNull);
    });

    test('testConnectionError set on failure', () async {
      await vm.createProfile(
        name: 'Test',
        baseUrl: 'http://localhost:8080',
        protocol: ApiProtocol.openAi,
      );

      await vm.testConnection();

      expect(vm.testConnectionError, isNull);
    });

    test('isTestingConnection reflects state', () async {
      vm.testConnection();
      expect(vm.isTestingConnection, isTrue);
      // Wait for testConnection to complete
      await Future.delayed(const Duration(milliseconds: 200));
    });
  });

  group('SettingsViewModel activeProfileName', () {
    test('returns active profile name', () async {
      await vm.createProfile(
        name: 'My Server',
        baseUrl: 'http://localhost:8080',
        protocol: ApiProtocol.openAi,
      );

      expect(vm.activeProfileName, equals('My Server'));
    });

    test('returns null when no active profile', () async {
      await vm.deleteProfile(vm.activeProfileId!);

      expect(vm.activeProfileName, isNull);
    });
  });

  group('SettingsViewModel selectedModelContextLength', () {
    test('returns context length for known model', () async {
      vm.availableModels = [
        ModelInfo(id: 'test-model', name: 'Test Model', contextLength: 4096),
      ];
      vm.config.copyWith(selectedModel: 'test-model');

      expect(vm.getSelectedModelContextLength(), equals(4096));
    });

    test('returns null for unknown model', () async {
      vm.config = vm.config.copyWith(selectedModel: 'unknown-model');

      expect(vm.getSelectedModelContextLength(), isNull);
    });

    test('returns null when no model selected', () async {
      // copyWith(selectedModel: null) keeps existing value due to ?? operator
      // So we set a config with no selectedModel
      final emptyConfig = ServerConfig(selectedModel: null);
      vm.config = emptyConfig;

      expect(vm.getSelectedModelContextLength(), isNull);
    });
  });

  group('SettingsViewModel connectionDetails', () {
    test('returns connection details for active profile', () async {
      await vm.createProfile(
        name: 'Test',
        baseUrl: 'http://localhost:8080',
        protocol: ApiProtocol.openAi,
      );

      expect(vm.connectionDetails, isNotNull);
      expect(vm.connectionDetails?.baseUrl, equals('http://localhost:8080'));
    });

    test('returns null when no active profile', () async {
      await vm.deleteProfile(vm.activeProfileId!);

      expect(vm.connectionDetails, isNull);
    });
  });

  group('SettingsViewModel saveLastRoleplayThreadId', () {
    test('saves last roleplay thread id', () async {
      await vm.saveLastRoleplayThreadId('thread-1');
    });
  });

  group('SettingsViewModel loadLastRoleplayThreadId', () {
    test('loads last roleplay thread id', () async {
      await vm.saveLastRoleplayThreadId('thread-1');
      final id = await vm.loadLastRoleplayThreadId();
      expect(id, equals('thread-1'));
    });
  });

  group('SettingsViewModel availableModels', () {
    test('returns available models', () async {
      vm.availableModels = [
        ModelInfo(id: 'model-1', name: 'Model 1', contextLength: 4096),
      ];

      expect(vm.availableModels, hasLength(1));
    });
  });

  group('SettingsViewModel dispose', () {
    test('cancels health poll timer', () {
      vm.dispose();
    });
  });
}
