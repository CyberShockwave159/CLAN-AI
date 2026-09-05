import 'dart:async';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/core/utils/mutex.dart';
import 'package:clan_ai/data/datasources/llama_api_service.dart';
import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/models/model_info.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';

class ServerRepository {
  final LlamaApiService _apiService;
  final LocalDatabase _localDb;
  static final _mutex = Mutex();

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
    ServerProfile? result;
    try {
      await _mutex.run(() async {
        final profiles = await loadProfiles();
        final profile = ServerProfile(
          name: name,
          baseUrl: baseUrl,
          apiKey: null,
          protocol: protocol,
        );
        profiles.add(profile);
        await saveProfiles(profiles);
        if (apiKey != null && apiKey.isNotEmpty) {
          await _localDb.saveProfileApiKey(profile.id, apiKey);
        }
        await setActiveProfileId(profile.id);
        result = ServerProfile(
          id: profile.id,
          name: profile.name,
          baseUrl: profile.baseUrl,
          apiKey: apiKey,
          protocol: profile.protocol,
        );
      });
    } catch (_) {}
    return result ?? ServerProfile(name: name, baseUrl: baseUrl, protocol: protocol);
  }

  Future<ServerProfile> updateProfile(ServerProfile profile) async {
    ServerProfile? result;
    try {
      await _mutex.run(() async {
        final profiles = await loadProfiles();
        final index = profiles.indexWhere((p) => p.id == profile.id);
        if (index != -1) {
          final updatedProfile = profiles[index].copyWith(
            name: profile.name,
            baseUrl: profile.baseUrl,
            protocol: profile.protocol,
          );
          profiles[index] = updatedProfile;
          await saveProfiles(profiles);
          if (profile.apiKey != null && profile.apiKey!.isNotEmpty) {
            await _localDb.saveProfileApiKey(profile.id, profile.apiKey);
          }
          result = ServerProfile(
            id: profiles[index].id,
            name: profiles[index].name,
            baseUrl: profiles[index].baseUrl,
            apiKey: profile.apiKey,
            protocol: profiles[index].protocol,
          );
        } else {
          result = profile;
        }
      });
    } catch (_) {}
    return result ?? profile;
  }

  Future<void> deleteProfile(String profileId) async {
    await _mutex.run(() async {
      final profiles = await loadProfiles();
      profiles.removeWhere((p) => p.id == profileId);
      await saveProfiles(profiles);
      await _localDb.saveProfileApiKey(profileId, null);
      final activeId = await getActiveProfileId();
      if (activeId == profileId) {
        if (profiles.isNotEmpty) {
          await setActiveProfileId(profiles.first.id);
        } else {
          await _localDb.setActiveProfileId('');
        }
      }
    });
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

  Future<ServerProfile?> getActiveConnection() async {
    return await getActiveProfile();
  }

  Future<ServerConfig> loadActiveConfig() async {
    ServerConfig globalConfig = await _localDb.loadActiveServerConfig();
    final profile = await getActiveProfile();
    String? apiKey = profile?.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      apiKey = await _localDb.getProfileApiKey(profile?.id ?? '');
    }
    globalConfig = globalConfig.copyWith(
      name: profile?.name ?? globalConfig.name,
      baseUrl: profile?.baseUrl ?? globalConfig.baseUrl,
      apiKey: apiKey,
      protocol: profile?.protocol ?? globalConfig.protocol,
    );
    return globalConfig;
  }

  Future<void> saveActiveConfig(ServerConfig config) async {
    final activeId = await getActiveProfileId();
    if (activeId != null && activeId.isNotEmpty) {
      final profiles = await loadProfiles();
      final index = profiles.indexWhere((p) => p.id == activeId);
      if (index != -1) {
        profiles[index] = profiles[index].copyWith(
          name: config.name,
          baseUrl: config.baseUrl,
          protocol: config.protocol,
        );
        await saveProfiles(profiles);
        if (config.apiKey != null && config.apiKey!.isNotEmpty) {
          await _localDb.saveProfileApiKey(activeId, config.apiKey);
        }
        return;
      }
    }
    await _localDb.saveActiveServerConfig(config);
  }

  // --- API Passthroughs ---

  Future<PingResult> ping(String baseUrl, {String? apiKey}) async {
    return await _apiService.ping(baseUrl, apiKey: apiKey);
  }

  Future<List<ModelInfo>> fetchModels(String baseUrl, {String? apiKey}) async {
    return await _apiService.fetchModels(baseUrl, apiKey: apiKey);
  }

  // --- Legacy API (kept for compatibility) ---

  Future<PingResult> testConnection(String baseUrl, {String? apiKey}) async {
    return await ping(baseUrl, apiKey: apiKey);
  }

  // fetchModels is already exposed above; this alias is for compatibility
}
