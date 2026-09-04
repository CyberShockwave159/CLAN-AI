import 'package:clan_ai/data/models/app_mode.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/models/system_prompt_template.dart';
import 'package:clan_ai/data/repositories/server_repository.dart';
import 'package:clan_ai/data/repositories/system_prompt_templates_repository.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_server_repository.dart';
import '../helpers/test_model_factories.dart';

void main() {
  late FakeServerRepository fakeServerRepo;
  late SystemPromptTemplatesRepository fakeTemplateRepo;
  late SettingsViewModel vm;

  setUp(() async {
    fakeServerRepo = FakeServerRepository();
    fakeServerRepo._activeConfig = const ServerConfig();
    vm = SettingsViewModel(
      serverRepository: fakeServerRepo,
      templateRepository: fakeTemplateRepo,
    );
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

  group('SettingsViewModel config', () async {
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

  group('SettingsViewModel profiles', () async {
    test('creates new profile', () async {
      await vm.createProfile(
        name: 'My Server',
        baseUrl: 'http://localhost:8080',
        protocol: ApiProtocol.openAi,
      );

      expect(vm.profiles, isNotEmpty);
      expect(vm.profiles.first.name, equals('My Server'));
    });

    test('updates profile', () async {
      final profile = await fakeServerRepo.createProfile('Test', baseUrl: 'http://localhost:8080');
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
      final profile1 = await fakeServerRepo.createProfile('Profile 1', baseUrl: 'http://localhost:8080');
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

  group('SettingsViewModel templates', () async {
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

  group('SettingsViewModel connection', () async {
    test('tests connection', () async {
      await vm.createProfile(
        name: 'Test',
        baseUrl: 'http://localhost:8080',
        protocol: ApiProtocol.openAi,
      );
      vm._activeProfileId = vm.profiles.first.id;

      await vm.testConnection();

      expect(vm.config.healthStatus, isNotNull);
    });

    test('testConnectionError set on failure', () async {
      await vm.createProfile(
        name: 'Test',
        baseUrl: 'http://localhost:8080',
        protocol: ApiProtocol.openAi,
      );
      vm._activeProfileId = vm.profiles.first.id;

      await vm.testConnection();

      expect(vm.testConnectionError, isNull);
    });

    test('isTestingConnection reflects state', () async {
      vm._isTestingConnection = true;
      expect(vm.isTestingConnection, isTrue);
    });
  });

  group('SettingsViewModel activeProfileName', () {
    test('returns active profile name', () async {
      await vm.createProfile(
        name: 'My Server',
        baseUrl: 'http://localhost:8080',
        protocol: ApiProtocol.openAi,
      );
      vm._activeProfileId = vm.profiles.first.id;

      expect(vm.activeProfileName, equals('My Server'));
    });

    test('returns null when no active profile', () {
      vm._activeProfileId = null;

      expect(vm.activeProfileName, isNull);
    });
  });

  group('SettingsViewModel selectedModelContextLength', () async {
    test('returns context length for known model', () async {
      vm._availableModels = [
        ModelInfo(id: 'test-model', name: 'Test Model', contextLength: 4096),
      ];
      vm._config = vm.config.copyWith(selectedModel: 'test-model');

      expect(vm.getSelectedModelContextLength(), equals(4096));
    });

    test('returns null for unknown model', () async {
      vm._config = vm.config.copyWith(selectedModel: 'unknown-model');

      expect(vm.getSelectedModelContextLength(), isNull);
    });

    test('returns null when no model selected', () async {
      vm._config = const ServerConfig(selectedModel: null);

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
      vm._activeProfileId = vm.profiles.first.id;

      expect(vm.connectionDetails, isNotNull);
      expect(vm.connectionDetails?.baseUrl, equals('http://localhost:8080'));
    });

    test('returns null when no active profile', () {
      vm._activeProfileId = null;

      expect(vm.connectionDetails, isNull);
    });
  });

  group('SettingsViewModel saveLastRoleplayThreadId', () {
    test('saves last roleplay thread id', () async {
      await vm.saveLastRoleplayThreadId('thread-1');
    });
  });

  group('SettingsViewModel loadLastRoleplayThreadId', () async {
    test('loads last roleplay thread id', () async {
      await vm.saveLastRoleplayThreadId('thread-1');
      final id = await vm.loadLastRoleplayThreadId();
      expect(id, equals('thread-1'));
    });
  });

  group('SettingsViewModel availableModels', () {
    test('returns available models', () async {
      vm._availableModels = [
        ModelInfo(id: 'model-1', name: 'Model 1', contextLength: 4096),
      ];

      expect(vm.availableModels, hasLength(1));
    });
  });

  group('SettingsViewModel dispose', () async {
    test('cancels health poll timer', () {
      vm._healthPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {});
      expect(vm._healthPollTimer, isNotNull);

      vm.dispose();
    });
  });
}
