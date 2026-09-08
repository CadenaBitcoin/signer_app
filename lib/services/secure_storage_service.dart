import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:signer/services/push/push_registration_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enhanced Secure Storage Service with first-launch check and data clearing
/// 
/// This service addresses the iOS Keychain persistence issue where data remains
/// after app uninstallation. It implements a first-launch check using
/// shared_preferences to detect fresh installs and clear secure storage.
class SecureStorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final String _firstLaunchKey = 'has_launched_before';
  
  /// Initialize the secure storage service
  /// 
  /// This method should be called during app startup to ensure data is cleared
  /// on fresh installs or reinstalls, particularly on iOS where Keychain data
  /// persists across app uninstalls.
  /// 
  /// The key insight: shared_preferences gets cleared on uninstall, but secure storage doesn't.
  /// So we use shared_preferences to detect if this is a fresh install.
  Future<void> initialize() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      bool hasLaunchedBefore = prefs.getBool(_firstLaunchKey) ?? false;

      if (!hasLaunchedBefore) {
        // Clear secure storage on first launch or reinstallation
        await _storage.deleteAll();
        // Set flag in shared_preferences (not secure storage!)
        await prefs.setBool(_firstLaunchKey, true);
      }
    } catch (e) {
      // Continue app execution even if initialization fails
    }
  }

  /// Write data to secure storage
  Future<void> writeData(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      rethrow;
    }
  }

  /// Read data from secure storage
  Future<String?> readData(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      return null;
    }
  }

  /// Delete specific data from secure storage
  Future<void> deleteData(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      rethrow;
    }
  }

  /// Delete all data from secure storage
  Future<void> deleteAll() async {
    try {
      await PushRegistrationRuntime.disconnect(() => _storage.deleteAll());
    } catch (e) {
      rethrow;
    }
  }

  /// Check if a key exists in secure storage
  Future<bool> containsKey(String key) async {
    try {
      return await _storage.containsKey(key: key);
    } catch (e) {
      return false;
    }
  }

  /// Get all keys from secure storage
  Future<Map<String, String>> readAll() async {
    try {
      return await _storage.readAll();
    } catch (e) {
      return {};
    }
  }

  /// Reset the first launch flag (useful for testing)
  /// This removes the flag from shared_preferences, not secure storage
  Future<void> resetFirstLaunchFlag() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_firstLaunchKey);
    } catch (e) {
      // Handle error silently
    }
  }

  /// Force clear all data and reset first launch flag (useful for testing)
  Future<void> forceReset() async {
    try {
      await deleteAll();
      await resetFirstLaunchFlag();
    } catch (e) {
      rethrow;
    }
  }
}
