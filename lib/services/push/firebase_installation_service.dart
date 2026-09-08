import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

String? installationPlatform(TargetPlatform platform, {bool web = false}) {
  if (web) return null;
  return switch (platform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => null,
  };
}

/// Client configuration only. No service-account credentials belong in the app.
FirebaseOptions installationOptions(String platform) {
  const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  final appId = platform == 'android'
      ? const String.fromEnvironment('FIREBASE_ANDROID_APP_ID')
      : const String.fromEnvironment('FIREBASE_IOS_APP_ID');
  final apiKey = platform == 'android'
      ? const String.fromEnvironment('FIREBASE_ANDROID_API_KEY')
      : const String.fromEnvironment('FIREBASE_IOS_API_KEY');
  if ([project, sender, appId, apiKey].any((value) => value.isEmpty)) {
    throw StateError('Firebase client configuration is missing');
  }
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: sender,
    projectId: project,
    iosBundleId: platform == 'ios' ? 'com.app.cadenabitcoin' : null,
  );
}

class FirebaseInstallationService {
  FirebaseInstallationService({
    required this.initialize,
    required this.readId,
  });

  factory FirebaseInstallationService.forPlatform(String platform) {
    return FirebaseInstallationService(
      initialize: () async {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(options: installationOptions(platform));
        }
      },
      readId: () => FirebaseInstallations.instance.getId(),
    );
  }

  final Future<void> Function() initialize;
  final Future<String> Function() readId;
  Future<void>? _initializing;

  Future<String> getId() async {
    try {
      await (_initializing ??= initialize());
    } catch (_) {
      _initializing = null; // A later lifecycle event may retry initialization.
      rethrow;
    }
    final fid = await readId();
    if (fid.trim().isEmpty) throw StateError('Firebase returned an empty FID');
    return fid; // Opaque: never normalize or substitute another identifier.
  }
}
