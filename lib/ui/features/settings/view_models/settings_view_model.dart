import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/data/models/model_info.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/models/system_prompt_template.dart';
import 'package:clan_ai/data/repositories/server_repository.dart';
import 'package:clan_ai/data/repositories/system_prompt_templates_repository.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

class SettingsViewModel extends ChangeNotifier {
  final ServerRepository _serverRepository;
  final SystemPromptTemplatesRepository _templateRepository;

  ServerConfig _config = const ServerConfig();
  ServerConfig get config => _config;

  List<ModelInfo> _availableModels = [];
  List<ModelInfo> get availableModels => _availableModels;

  List<SystemPromptTemplate> _templates = [];
  List<SystemPromptTemplate> get templates => _templates;

  List<ServerProfile> _profiles = [];
  List<ServerProfile> get profiles => _profiles;

  String? _activeProfileId;
  String? get activeProfileId => _activeProfileId;

  String? get activeProfileName {
    for (final p in _profiles) {
      if (p.id == _activeProfileId) return p.name;
    }
    return null;
  }

  bool _isTestingConnection = false;
  bool get isTestingConnection => _isTestingConnection;

  String? _testConnectionError;
  String? get testConnectionError => _testConnectionError;

  Timer? _healthPollTimer;

  SettingsViewModel({
    ServerRepository? serverRepository,
    SystemPromptTemplatesRepository? templateRepository,
  })  : _serverRepository = serverRepository ?? ServerRepository(),
        _templateRepository = templateRepository ?? SystemPromptTemplatesRepository() {
    _init();
  }

  Future<void> _init() async {
    _profiles = await _serverRepository.loadProfiles();
    _activeProfileId = await _serverRepository.getActiveProfileId();

    // Migrate existing config to a default profile if no profiles exist
    if (_profiles.isEmpty) {
      final legacyConfig = await _serverRepository.loadActiveConfig();
      if (legacyConfig.baseUrl.isNotEmpty) {
        final profile = await _serverRepository.createProfile(
          'Default',
          baseUrl: legacyConfig.baseUrl,
          apiKey: legacyConfig.apiKey,
          protocol: legacyConfig.protocol,
        );
        _profiles = await _serverRepository.loadProfiles();
        _activeProfileId = profile.id;
        _config = legacyConfig;
      }
    } else {
      _config = await _serverRepository.loadActiveConfig();
    }

    _templates = await _templateRepository.loadTemplates();
    notifyListeners();
    // Test initial connection & fetch models
    await testConnection();
    _startHealthPolling();
  }

  void _startHealthPolling() {
    _healthPollTimer?.cancel();
    _healthPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      pingActiveServer();
    });
  }

  Future<void> updateBaseUrl(String url) async {
    _config = _config.copyWith(baseUrl: url);
    await _saveConfig();
    notifyListeners();
  }

  Future<void> updateApiKey(String? key) async {
    _config = _config.copyWith(apiKey: key);
    await _saveConfig();
    notifyListeners();
  }

  Future<void> updateProtocol(ApiProtocol protocol) async {
    _config = _config.copyWith(protocol: protocol);
    await _saveConfig();
    notifyListeners();
  }

  Future<void> updateSelectedModel(String modelId) async {
    _config = _config.copyWith(selectedModel: modelId);
    await _saveConfig();
    notifyListeners();
  }

  Future<void> updateSystemPrompt(String systemPrompt) async {
    _config = _config.copyWith(systemPrompt: systemPrompt);
    await _saveConfig();
    notifyListeners();
  }

  Future<void> updateDefaultParams(GenerationParams params) async {
    _config = _config.copyWith(defaultParams: params);
    await _saveConfig();
    notifyListeners();
  }

  Future<void> toggleConfirmDeleteMessage(bool value) async {
    _config = _config.copyWith(confirmDeleteMessage: value);
    await _saveConfig();
    notifyListeners();
  }

  Future<void> addTemplate(String name, String content) async {
    await _templateRepository.addTemplate(name, content);
    _templates = await _templateRepository.loadTemplates();
    notifyListeners();
  }

  Future<void> updateTemplate(int index, String name, String content) async {
    await _templateRepository.updateTemplate(index, name, content);
    _templates = await _templateRepository.loadTemplates();
    notifyListeners();
  }

  Future<void> deleteTemplate(int index) async {
    await _templateRepository.deleteTemplate(index);
    _templates = await _templateRepository.loadTemplates();
    notifyListeners();
  }

  // --- Profile Management ---

  Future<void> reloadProfiles() async {
    _profiles = await _serverRepository.loadProfiles();
    _activeProfileId = await _serverRepository.getActiveProfileId();
    notifyListeners();
  }

  Future<void> switchProfile(String profileId) async {
    await _serverRepository.setActiveProfileId(profileId);
    _activeProfileId = profileId;
    _config = await _serverRepository.loadActiveConfig();
    _availableModels.clear();
    _testConnectionError = null;
    notifyListeners();
    // Test connection with new profile
    await testConnection();
  }

  Future<void> createProfile({
    required String name,
    required String baseUrl,
    String? apiKey,
    required ApiProtocol protocol,
  }) async {
    await _serverRepository.createProfile(
      name,
      baseUrl: baseUrl,
      apiKey: apiKey,
      protocol: protocol,
    );
    _profiles = await _serverRepository.loadProfiles();
    _activeProfileId = await _serverRepository.getActiveProfileId();
    _config = await _serverRepository.loadActiveConfig();
    notifyListeners();
  }

  Future<void> updateProfile(ServerProfile updatedProfile) async {
    await _serverRepository.updateProfile(updatedProfile);
    _profiles = await _serverRepository.loadProfiles();
    if (_activeProfileId == updatedProfile.id) {
      _config = await _serverRepository.loadActiveConfig();
    }
    notifyListeners();
  }

  Future<void> updateProfileName(String profileId, String newName) async {
    final profiles = await _serverRepository.loadProfiles();
    final index = profiles.indexWhere((p) => p.id == profileId);
    if (index != -1) {
      final updated = profiles[index].copyWith(name: newName);
      await _serverRepository.updateProfile(updated);
      _profiles = await _serverRepository.loadProfiles();
      notifyListeners();
    }
  }

  Future<void> deleteProfile(String profileId) async {
    await _serverRepository.deleteProfile(profileId);
    _profiles = await _serverRepository.loadProfiles();
    _activeProfileId = await _serverRepository.getActiveProfileId();
    if (_profiles.isNotEmpty) {
      _config = await _serverRepository.loadActiveConfig();
    }
    notifyListeners();
  }

  Future<void> testConnection() async {
    _isTestingConnection = true;
    _testConnectionError = null;
    _config = _config.copyWith(healthStatus: ServerHealthStatus.connecting);
    notifyListeners();

    try {
      final pingRes = await _serverRepository.testConnection(_config.baseUrl, apiKey: _config.apiKey);
      _config = _config.copyWith(
        healthStatus: pingRes.status,
        latencyMs: pingRes.latencyMs,
      );

      if (pingRes.isHealthy) {
        _testConnectionError = null;
        // Fetch models
        _availableModels = await _serverRepository.fetchModels(_config.baseUrl, apiKey: _config.apiKey);
        if (_availableModels.isNotEmpty && (_config.selectedModel == null || _config.selectedModel!.isEmpty)) {
          _config = _config.copyWith(selectedModel: _availableModels.first.id);
        }
      } else {
        _testConnectionError = pingRes.errorMessage ?? 'Server unreachable';
      }
    } catch (e) {
      _config = _config.copyWith(
        healthStatus: ServerHealthStatus.offline,
        latencyMs: -1,
      );
      _testConnectionError = e.toString();
    } finally {
      _isTestingConnection = false;
      await _saveConfig();
      notifyListeners();
    }
  }

  Future<void> pingActiveServer() async {
    if (_isTestingConnection) return;
    try {
      final pingRes = await _serverRepository.testConnection(_config.baseUrl, apiKey: _config.apiKey);
      _config = _config.copyWith(
        healthStatus: pingRes.status,
        latencyMs: pingRes.latencyMs,
      );
      notifyListeners();
    } catch (_) {
      _config = _config.copyWith(
        healthStatus: ServerHealthStatus.offline,
        latencyMs: -1,
      );
      notifyListeners();
    }
  }

  Future<void> _saveConfig() async {
    await _serverRepository.saveActiveConfig(_config);
  }

  /// Returns the context length of the currently selected model, or null if unknown.
  int? getSelectedModelContextLength() {
    final modelId = _config.selectedModel;
    if (modelId == null) return null;
    for (final model in _availableModels) {
      if (model.id == modelId) {
        return model.contextLength;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _healthPollTimer?.cancel();
    super.dispose();
  }
}
