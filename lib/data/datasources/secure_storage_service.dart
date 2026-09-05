import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static final SecureStorageService instance = SecureStorageService._init();

  SecureStorageService._init();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked,
    ),
  );

  Future<void> saveApiKey(String profileId, String key) async {
    await _storage.write(key: 'api_key_$profileId', value: key);
  }

  Future<String?> getApiKey(String profileId) async {
    return await _storage.read(key: 'api_key_$profileId');
  }

  Future<void> deleteApiKey(String profileId) async {
    await _storage.delete(key: 'api_key_$profileId');
  }

  Future<void> close() async {}
}
