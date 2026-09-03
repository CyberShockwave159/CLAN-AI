import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/models/model_info.dart';
import 'package:clan_ai/data/repositories/server_repository.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';

class FakeServerRepository extends ServerRepository {
  final List<ServerProfile> _profiles = [];
  String? _activeProfileId;
  ServerConfig? _activeConfig;
  PingResult? _lastPingResult;

  List<ServerProfile> get all => _profiles;
  String? get activeProfileId => _activeProfileId;
  ServerConfig? get activeConfig => _activeConfig;
  PingResult? get lastPingResult => _lastPingResult;

  @override
  Future<List<ServerProfile>> loadProfiles() async => _profiles.toList();

  @override
  Future<String?> getActiveProfileId() async => _activeProfileId;

  @override
  Future<ServerProfile?> getActiveProfile() async {
    if (_activeProfileId == null) return null;
    return _profiles.where((p) => p.id == _activeProfileId).firstOrNull;
  }

  @override
  Future<ServerProfile> createProfile(
    String name, {
    String? baseUrl,
    String? apiKey,
    ApiProtocol protocol = ApiProtocol.openAi,
  }) async {
    final profile = ServerProfile(
      name: name,
      baseUrl: baseUrl,
      apiKey: apiKey,
      protocol: protocol,
    );
    _profiles.add(profile);
    return profile;
  }

  @override
  Future<void> updateProfile(ServerProfile profile) async {
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index != -1) {
      _profiles[index] = profile;
    }
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    _profiles.removeWhere((p) => p.id == profileId);
    if (_activeProfileId == profileId) {
      _activeProfileId = _profiles.isNotEmpty ? _profiles.first.id : null;
    }
  }

  @override
  Future<void> setActiveProfileId(String profileId) async {
    _activeProfileId = profileId;
  }

  @override
  Future<ServerConfig> loadActiveConfig() async {
    return _activeConfig ?? const ServerConfig();
  }

  @override
  Future<void> saveActiveConfig(ServerConfig config) async {
    _activeConfig = config;
  }

  @override
  Future<PingResult> testConnection(String baseUrl, {String? apiKey}) async {
    _lastPingResult = const PingResult(
      status: ServerHealthStatus.connected,
      latencyMs: 50,
      errorMessage: null,
    );
    return _lastPingResult!;
  }

  @override
  Future<List<ModelInfo>> fetchModels(String baseUrl, {String? apiKey}) async {
    return [
      ModelInfo(id: 'test-model', name: 'Test Model', contextLength: 4096),
    ];
  }
}
