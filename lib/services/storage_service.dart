import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signer/services/push/push_registration_runtime.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:signer/services/secure_storage_service.dart';

class StorageService {
  static final _storage = const FlutterSecureStorage();
  
  /// Get the enhanced secure storage service
  static SecureStorageService get _secureStorageService => Get.find<SecureStorageService>();
  static const String _userListKey = 'registered_users';

  getUserData({String? email}) async {
    print("====>>>>>$email");
    var userData = await _storage.read(key: 'user_$email');
    print("=======$userData");
  }

  /// Save a new user
  static Future<void> saveWalletData({
    required String email,
    required String password,
    required String mnemonic,
    required String address,
    required String privateKey,
    required String xpub,
  }) async {
    final userKey = 'user_$email';

    final Map<String, String> userData = {
      'email': email,
      'password': password,
      'mnemonic': mnemonic,
      'btc_address': address,
      'private_key': privateKey,
      'xpub': xpub,
    };

    // Save this user’s data
    await _storage.write(key: userKey, value: jsonEncode(userData));
    await _storage.write(key: 'logged_in_user_email', value: email);
    await _storage.write(key: 'logged_in_user_password', value: password);

    // Update the user list
    final userListRaw = await _storage.read(key: _userListKey);
    final List<String> userList =
        userListRaw != null ? List<String>.from(jsonDecode(userListRaw)) : [];

    if (!userList.contains(email)) {
      userList.add(email);
      await _storage.write(key: _userListKey, value: jsonEncode(userList));
    }
  }

  /// Get all users' data
  static Future<List<Map<String, String>>> getAllUsers() async {
    final userListRaw = await _storage.read(key: _userListKey);
    if (userListRaw == null) return [];

    final List<String> userList = List<String>.from(jsonDecode(userListRaw));
    final List<Map<String, String>> users = [];

    for (var email in userList) {
      final userRaw = await _storage.read(key: 'user_$email');
      if (userRaw != null) {
        final userMap = Map<String, String>.from(jsonDecode(userRaw));
        users.add(userMap);
      }
    }

    return users;
  }

  /// Try login
  static Future<Map<String, String>?> login(
    String email,
    String password,
  ) async {
    final users = await getAllUsers();

    for (var user in users) {
      if (user['email'] == email && user['password'] == password) {
        return user;
      }
    }

    return null; // Login failed
  }

  /// Clear all users (optional for reset)
  static Future<void> clearAllUsers() async {
    await PushRegistrationRuntime.disconnect(() async {
      await _storage.write(key: 'isLoggedIn', value: 'false');
      await _clearAllUsers();
    });
  }

  static Future<void> _clearAllUsers() async {
    final userListRaw = await _storage.read(key: _userListKey);
    if (userListRaw != null) {
      final List<String> userList = List<String>.from(jsonDecode(userListRaw));
      for (var email in userList) {
        await _storage.delete(key: 'user_$email');
      }
      await _storage.delete(key: _userListKey);
    }
  }

  static Future<void> logoutUser() async {
    // Don't delete user data, just set isLoggedIn to false
    await PushRegistrationRuntime.disconnect(() =>
        _storage.write(key: 'isLoggedIn', value: 'false'));
  }

  static Future<void> resetUserData() async {
    await PushRegistrationRuntime.disconnect(() async {
      await _storage.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });
  }

  static Future<String?> getLoggedInEmail() async {
    return await _storage.read(key: 'logged_in_user_email');
  }

  static Future<Map<String, String>?> getUserByEmail(String email) async {
    final userKey = 'user_$email';
    final userJson = await _storage.read(key: userKey);

    if (userJson == null) return null;

    final Map<String, dynamic> userMap = jsonDecode(userJson);
    return userMap.map((key, value) => MapEntry(key, value.toString()));
  }

  static Future<void> setLoginStatus(bool isLoggedIn) async {
    if (!isLoggedIn) return logoutUser();
    await _storage.write(key: 'isLoggedIn', value: isLoggedIn.toString());
    PushRegistrationRuntime.authenticated();
  }

  static Future<bool> getLoginStatus() async {
    final status = await _storage.read(key: 'isLoggedIn');
    return status == 'true';
  }

  /// Enhanced methods using the SecureStorageService
  /// These methods provide better error handling and first-launch detection
  
  /// Write data using enhanced secure storage service
  static Future<void> writeSecureData(String key, String value) async {
    await _secureStorageService.writeData(key, value);
  }

  /// Read data using enhanced secure storage service
  static Future<String?> readSecureData(String key) async {
    return await _secureStorageService.readData(key);
  }

  /// Delete data using enhanced secure storage service
  static Future<void> deleteSecureData(String key) async {
    await _secureStorageService.deleteData(key);
  }

  /// Clear all secure storage data
  static Future<void> clearAllSecureData() async {
    await _secureStorageService.deleteAll();
  }

  /// Force reset all data (useful for testing)
  static Future<void> forceResetAllData() async {
    await _secureStorageService.forceReset();
  }
}
