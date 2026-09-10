import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/models/app_mode.dart';
import 'package:clan_ai/data/models/model_info.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/models/system_prompt_template.dart';
import 'package:clan_ai/data/repositories/server_repository.dart';
import 'package:clan_ai/data/repositories/system_prompt_templates_repository.dart';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/data/models/custom_theme_colors.dart';
import 'package:clan_ai/data/models/app_theme_mode.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

class SettingsViewModel extends ChangeNotifier {
  final ServerRepository _serverRepository;
  final SystemPromptTemplatesRepository _templateRepository;
  VoidCallback? _onThemeChanged;

  ServerConfig config = const ServerConfig();

  AppMode _appMode = AppMode.assistant;
  AppMode get appMode => _appMode;

  AppThemeMode _themeMode = AppThemeMode.dark;
  AppThemeMode get themeMode => _themeMode;

  CustomThemeColors? _customThemeColors;
  CustomThemeColors? get customThemeColors => _customThemeColors;

  VoidCallback? get onThemeChanged => _onThemeChanged;

  void setOnThemeChanged(VoidCallback callback) {
    _onThemeChanged = callback;
  }

  List<ModelInfo> availableModels = [];

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

  ServerProfile? get connectionDetails {
    if (_activeProfileId == null) return null;
    return _profiles.firstWhere(
      (p) => p.id == _activeProfileId,
      orElse: () => throw StateError('Active profile not found'),
    );
  }

  bool _isTestingConnection = false;
  bool get isTestingConnection => _isTestingConnection;

  String? _testConnectionError;
  String? get testConnectionError => _testConnectionError;

  Timer? _healthPollTimer;

  SettingsViewModel({
    ServerRepository? serverRepository,
    SystemPromptTemplatesRepository? templateRepository,
    VoidCallback? onThemeChanged,
  })  : _serverRepository = serverRepository ?? ServerRepository(),
        _templateRepository = templateRepository ?? SystemPromptTemplatesRepository() {
    _onThemeChanged = onThemeChanged;
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
          reasoning: legacyConfig.reasoning,
        );
        _profiles = await _serverRepository.loadProfiles();
        _activeProfileId = profile.id;
        config = legacyConfig;
      }
    } else {
      config = await _serverRepository.loadActiveConfig();
    }

    _templates = await _templateRepository.loadTemplates();
    _appMode = await LocalDatabase.instance.loadAppMode();
    _themeMode = await LocalDatabase.instance.loadAppThemeMode();
    _customThemeColors = await LocalDatabase.instance.loadCustomThemeColors();
    notifyListeners();
    // Test initial connection & fetch models
    await testConnection();
    _startHealthPolling();
  }

  void _startHealthPolling() {
    _healthPollTimer?.cancel();
    _healthPollTimer = Timer.periodic(healthPollInterval, (_) {
      pingActiveServer();
    });
  }

  Future<void> updateAppMode(AppMode mode) async {
    _appMode = mode;
    await LocalDatabase.instance.saveAppMode(mode);
    notifyListeners();
  }

  Future<void> setAppThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    await LocalDatabase.instance.saveAppThemeMode(mode);
    _onThemeChanged?.call();
    notifyListeners();
  }

  Future<void> setCustomThemeColors(CustomThemeColors colors) async {
    _customThemeColors = colors;
    await LocalDatabase.instance.saveCustomThemeColors(colors);
    _onThemeChanged?.call();
    notifyListeners();
  }

  Future<void> clearCustomThemeColors() async {
    _customThemeColors = null;
    await LocalDatabase.instance.saveCustomThemeColors(const CustomThemeColors(
      bg: AppTheme.darkBg,
      surface: AppTheme.darkSurface,
      surfaceVariant: AppTheme.darkSurfaceVariant,
      border: AppTheme.darkBorder,
      textPrimary: AppTheme.darkTextPrimary,
      textSecondary: AppTheme.darkTextSecondary,
      textMuted: AppTheme.darkTextMuted,
      userBubble: AppTheme.darkUserBubble,
      assistantBubble: AppTheme.darkAssistantBubble,
    ));
    _onThemeChanged?.call();
    notifyListeners();
  }

  Future<void> saveLastRoleplayThreadId(String? threadId) async {
    await LocalDatabase.instance.saveLastRoleplayThreadId(threadId);
  }

  Future<String?> loadLastRoleplayThreadId() async {
    return await LocalDatabase.instance.loadLastRoleplayThreadId();
  }

  Future<void> updateBaseUrl(String url) async {
    final profile = await _serverRepository.getActiveProfile();
    if (profile != null) {
      final updated = profile.copyWith(baseUrl: url);
      await _serverRepository.updateProfile(updated);
      _profiles = await _serverRepository.loadProfiles();
      config = config.copyWith(baseUrl: url);
      await _saveConfig();
    }
    notifyListeners();
  }

  Future<void> updateApiKey(String? key) async {
    final profile = await _serverRepository.getActiveProfile();
    if (profile != null) {
      final updated = profile.copyWith(apiKey: key);
      await _serverRepository.updateProfile(updated);
      _profiles = await _serverRepository.loadProfiles();
      config = config.copyWith(apiKey: key);
      await _saveConfig();
    }
    notifyListeners();
  }

  Future<void> updateProtocol(ApiProtocol protocol) async {
    final profile = await _serverRepository.getActiveProfile();
    if (profile != null) {
      final updated = profile.copyWith(protocol: protocol);
      await _serverRepository.updateProfile(updated);
      _profiles = await _serverRepository.loadProfiles();
      config = config.copyWith(protocol: protocol);
      await _saveConfig();
    }
    notifyListeners();
  }

  Future<void> updateSelectedModel(String modelId) async {
    config = config.copyWith(selectedModel: modelId);
    await _saveConfig();
    notifyListeners();
  }

  Future<void> updateSystemPrompt(String systemPrompt) async {
    config = config.copyWith(systemPrompt: systemPrompt);
    await _saveConfig();
    notifyListeners();
  }

  Future<void> updateDefaultParams(GenerationParams params) async {
    config = config.copyWith(defaultParams: params);
    await _saveConfig();
    notifyListeners();
  }

  Future<void> toggleConfirmDeleteMessage(bool value) async {
    config = config.copyWith(confirmDeleteMessage: value);
    await _saveConfig();
    notifyListeners();
  }

  Future<void> toggleReasoning(bool value) async {
    config = config.copyWith(reasoning: value);
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
    config = await _serverRepository.loadActiveConfig();
    availableModels.clear();
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
    config = await _serverRepository.loadActiveConfig();
    notifyListeners();
  }

  Future<void> updateProfile(ServerProfile updatedProfile) async {
    await _serverRepository.updateProfile(updatedProfile);
    _profiles = await _serverRepository.loadProfiles();
    if (_activeProfileId == updatedProfile.id) {
      config = await _serverRepository.loadActiveConfig();
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
      config = await _serverRepository.loadActiveConfig();
    }
    notifyListeners();
  }

  Future<PingResult?> testConnectionAtUrl(String url, {String? apiKey}) async {
    try {
      final result = await _serverRepository.testConnectionAtUrl(url, apiKey: apiKey);
      return result;
    } catch (e) {
      return PingResult(
        status: ServerHealthStatus.offline,
        latencyMs: -1,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> testConnection() async {
    _isTestingConnection = true;
    _testConnectionError = null;
    config = config.copyWith(healthStatus: ServerHealthStatus.connecting);
    notifyListeners();

    final conn = connectionDetails;
    if (conn == null) {
      config = config.copyWith(
        healthStatus: ServerHealthStatus.offline,
        latencyMs: -1,
      );
      _testConnectionError = 'No active profile';
      _isTestingConnection = false;
      await _saveConfig();
      notifyListeners();
      return;
    }

    try {
      final pingRes = await _serverRepository.testConnection(conn.baseUrl, apiKey: conn.apiKey);
      config = config.copyWith(
        healthStatus: pingRes.status,
        latencyMs: pingRes.latencyMs,
      );

      if (pingRes.isHealthy) {
        _testConnectionError = null;
        // Fetch models
        availableModels = await _serverRepository.fetchModels(conn.baseUrl, apiKey: conn.apiKey);
        if (availableModels.isNotEmpty) {
          if (config.selectedModel == null || config.selectedModel!.isEmpty) {
            config = config.copyWith(selectedModel: availableModels.first.id);
          } else if (!availableModels.any((m) => m.id == config.selectedModel)) {
            config = config.copyWith(selectedModel: availableModels.first.id);
          }
        }
      } else {
        _testConnectionError = pingRes.errorMessage ?? 'Server unreachable';
      }
    } catch (e) {
      config = config.copyWith(
        healthStatus: ServerHealthStatus.offline,
        latencyMs: -1,
      );
      _testConnectionError = PingResult.parseError(e.toString());
    } finally {
      _isTestingConnection = false;
      await _saveConfig();
      notifyListeners();
    }
  }

  Future<void> pingActiveServer() async {
    if (_isTestingConnection) return;
    final conn = connectionDetails;
    if (conn == null) {
      if (config.healthStatus != ServerHealthStatus.offline || config.latencyMs != -1) {
        config = config.copyWith(
          healthStatus: ServerHealthStatus.offline,
          latencyMs: -1,
        );
        notifyListeners();
      }
      return;
    }
    try {
      final pingRes = await _serverRepository.testConnection(conn.baseUrl, apiKey: conn.apiKey);
      final newStatus = pingRes.status;
      final newLatency = pingRes.latencyMs;
      if (config.healthStatus != newStatus || config.latencyMs != newLatency) {
        config = config.copyWith(
          healthStatus: newStatus,
          latencyMs: newLatency,
        );
        notifyListeners();
      }
    } catch (_) {
      if (config.healthStatus != ServerHealthStatus.offline || config.latencyMs != -1) {
        config = config.copyWith(
          healthStatus: ServerHealthStatus.offline,
          latencyMs: -1,
        );
        notifyListeners();
      }
    }
  }

  Future<void> _saveConfig() async {
    await _serverRepository.saveActiveConfig(config);
  }

  /// Returns the context length of the currently selected model, or null if unknown.
  int? getSelectedModelContextLength() {
    final modelId = config.selectedModel;
    if (modelId == null) return null;
    for (final model in availableModels) {
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
