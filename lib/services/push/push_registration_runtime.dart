import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_installation_service.dart';
import 'push_registration_api.dart';
import 'push_registration_lifecycle.dart';

/// The single bridge from existing authentication/storage hooks to push services.
class PushRegistrationRuntime {
  static PushRegistrationLifecycle? lifecycle;
  static int sessionGeneration = 0;
  static bool _tearingDown = false;
  static FirebaseInstallationService? _firebase;

  static void initialize(String baseUrl) {
    unawaited(_firebase?.dispose() ?? Future<void>.value());
    final platform = installationPlatform(defaultTargetPlatform, web: kIsWeb);
    late final FirebaseInstallationService? firebase;
    firebase = platform == null
        ? null
        : FirebaseInstallationService.forPlatform(platform, onRegistered: () {
            if (identical(_firebase, firebase)) authenticated(force: true);
          });
    _firebase = firebase;
    lifecycle = PushRegistrationLifecycle(
      readToken: authenticatedToken,
      readFid: () => firebase!.getId(),
      platform: platform,
      api: PushRegistrationApi(baseUrl),
      loadState: (token) => loadRegistrationState(baseUrl, token),
      saveState: (token, state) => saveRegistrationState(baseUrl, token, state),
      log: (event) => debugPrint(event),
    );
    authenticated();
  }

  // Scope durable cleanup state by backend and authenticated subject, never by
  // JWT bytes (which rotate). Use the app's existing secure-storage facility.
  static String _registrationKey(String baseUrl, String token) {
    final claims = jsonDecode(utf8
        .decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))));
    final subject = claims['sub'];
    if (subject is! String || subject.isEmpty) {
      throw StateError('Missing authenticated subject');
    }
    return 'push_registration:${jsonEncode([
          baseUrl.replaceFirst(RegExp(r'/$'), ''),
          subject,
        ])}';
  }

  static Future<BackendRegistrationState> loadRegistrationState(
      String baseUrl, String token) async {
    const storage = FlutterSecureStorage();
    final raw = await storage.read(key: _registrationKey(baseUrl, token));
    if (raw == null) return BackendRegistrationState();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return BackendRegistrationState(
      registeredFid: data['registered_fid'] as String?,
      pending: (data['pending_cleanup'] as List).cast<String>(),
    );
  }

  static Future<void> saveRegistrationState(
      String baseUrl, String token, BackendRegistrationState state) async {
    const storage = FlutterSecureStorage();
    final key = _registrationKey(baseUrl, token);
    if (state.registeredFid == null && state.pendingCleanup.isEmpty) {
      await storage.delete(key: key);
    } else {
      await storage.write(
          key: key,
          value: jsonEncode({
            'registered_fid': state.registeredFid,
            'pending_cleanup': state.pendingCleanup.toList(),
          }));
    }
  }

  static Future<String?> authenticatedToken() async {
    const storage = FlutterSecureStorage();
    if (await storage.read(key: 'isLoggedIn') != 'true') return null;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');
    if (token == null) return null;
    try {
      // Local freshness check only; backend remains the authority on identity.
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = claims['exp'];
      return exp is num && exp * 1000 > DateTime.now().millisecondsSinceEpoch
          ? token
          : null;
    } catch (_) {
      return null;
    }
  }

  static void authenticated({bool force = false}) {
    if (!_tearingDown) {
      unawaited(lifecycle?.register(force: force) ?? Future<void>.value());
    }
  }

  /// Token writers use a generation captured before their login/refresh request.
  /// A response arriving after logout must not resurrect that old session.
  static Future<bool> persistToken(String token, int generation) async {
    if (_tearingDown || generation != sessionGeneration) return false;
    final prefs = await SharedPreferences.getInstance();
    if (_tearingDown || generation != sessionGeneration) return false;
    await prefs.setString('jwtToken', token);
    if (_tearingDown || generation != sessionGeneration) {
      if (prefs.getString('jwtToken') == token) await prefs.remove('jwtToken');
      return false;
    }
    authenticated();
    return true;
  }

  static Future<void> disconnect(Future<void> Function() clearSession) async {
    _tearingDown = true;
    sessionGeneration++;
    Future<void> clear() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwtToken');
      await clearSession();
    }

    try {
      final service = lifecycle;
      if (service == null) {
        await clear();
      } else {
        await service.disconnect(clear);
      }
    } finally {
      _tearingDown = false;
    }
  }
}
