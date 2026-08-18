import 'dart:async';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/data/datasources/llama_api_service.dart';
import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/models/model_info.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';

class ServerRepository {
  final LlamaApiService _apiService;
  final LocalDatabase _localDb;

  ServerRepository({
    LlamaApiService? apiService,
    LocalDatabase? localDb,
  })  : _apiService = apiService ?? LlamaApiService(),
        _localDb = localDb ?? LocalDatabase.instance;

  // --- Profile Management ---

  Future<List<ServerProfile>> loadProfiles() async {
    return await _localDb.loadServerProfiles();
  }

  Future<void> saveProfiles(List<ServerProfile> profiles) async {
    await _localDb.saveServerProfiles(profiles);
  }

  Future<void> setActiveProfileId(String profileId) async {
    await _localDb.setActiveProfileId(profileId);
  }

  Future<String?> getActiveProfileId() async {
    return await _localDb.getActiveProfileId();
  }

  Future<ServerProfile> createProfile(String name, {
    required String baseUrl,
    String? apiKey,
    required ApiProtocol protocol,
  }) async {
    final profiles = await loadProfiles();
    final profile = ServerProfile(
      name: name,
      baseUrl: baseUrl,
      apiKey: apiKey,
      protocol: protocol,
    );
    profiles.add(profile);
    await saveProfiles(profiles);
    await setActiveProfileId(profile.id);
    return profile;
  }

  Future<ServerProfile> updateProfile(ServerProfile profile) async {
    final profiles = await loadProfiles();
    final index = profiles.indexWhere((p) => p.id == profile.id);
    if (index != -1) {
      profiles[index] = profile.copyWith(updatedAt: DateTime.now());
      await saveProfiles(profiles);
    }
    return profiles[index];
  }

  Future<void> deleteProfile(String profileId) async {
    final profiles = await loadProfiles();
    profiles.removeWhere((p) => p.id == profileId);
    await saveProfiles(profiles);
    final activeId = await getActiveProfileId();
    if (activeId == profileId) {
      if (profiles.isNotEmpty) {
        await setActiveProfileId(profiles.first.id);
      } else {
        await _localDb.setActiveProfileId('');
      }
    }
  }

  Future<ServerProfile?> getActiveProfile() async {
    final activeId = await getActiveProfileId();
    if (activeId == null || activeId.isEmpty) return null;
    final profiles = await loadProfiles();
    try {
      return profiles.firstWhere((p) => p.id == activeId);
    } catch (_) {
      return null;
    }
  }

  // --- Config Loading/Saving (Profile-aware) ---

  Future<ServerConfig> loadActiveConfig() async {
    // Start with global defaults (from legacy storage or defaults)
    ServerConfig globalConfig = await _localDb.loadActiveServerConfig();

    // Apply profile settings on top (baseUrl, apiKey, protocol)
    final profile = await getActiveProfile();
    if (profile != null) {
      globalConfig = globalConfig.copyWith(
        baseUrl: profile.baseUrl,
        apiKey: profile.apiKey,
        protocol: profile.protocol,
      );
    }

    return globalConfig;
  }

  Future<void> saveActiveConfig(ServerConfig config) async {
    // Update the active profile's baseUrl, apiKey, protocol
    final activeId = await getActiveProfileId();
    if (activeId != null && activeId.isNotEmpty) {
      final profiles = await loadProfiles();
      final index = profiles.indexWhere((p) => p.id == activeId);
      if (index != -1) {
        profiles[index] = profiles[index].copyWith(
          baseUrl: config.baseUrl,
          apiKey: config.apiKey,
          protocol: config.protocol,
        );
        await saveProfiles(profiles);
        return;
      }
    }

    // Fall back to legacy storage (for non-profile settings)
    await _localDb.saveActiveServerConfig(config);
  }

  // --- Legacy API (kept for compatibility) ---

  Future<PingResult> testConnection(String baseUrl, {String? apiKey}) async {
    return await _apiService.ping(baseUrl, apiKey: apiKey);
  }

  Future<List<ModelInfo>> fetchModels(String baseUrl, {String? apiKey}) async {
    return await _apiService.fetchModels(baseUrl, apiKey: apiKey);
  }
}
