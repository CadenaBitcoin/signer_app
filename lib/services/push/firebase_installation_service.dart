import 'dart:async';
import 'package:fcm_registration/fcm_registration.dart';
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
FirebaseOptions? installationOptions(String platform) {
  // Android loads the resources generated from google-services.json. Keep one
  // source of configuration for the native default app and FlutterFire.
  if (platform == 'android') return null;
  const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  const appId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  const apiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
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
    required this.register,
    required this.registeredFids,
    this.onRegistered,
    this.timeout = const Duration(seconds: 10),
  });

  factory FirebaseInstallationService.forPlatform(String platform,
      {void Function()? onRegistered}) {
    return FirebaseInstallationService(
      initialize: () async {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(options: installationOptions(platform));
        }
      },
      register: FcmRegistration.register,
      registeredFids: FcmRegistration.registeredFids,
      onRegistered: onRegistered,
    );
  }

  final Future<void> Function() initialize;
  final Future<void> Function() register;
  final Stream<String> registeredFids;
  final void Function()? onRegistered;
  final Duration timeout;
  Future<void>? _initializing;
  StreamSubscription<String>? _subscription;
  String? _registeredFid;
  Completer<String>? _waiting;

  Future<void> _start() async {
    await initialize();
    _subscription ??= registeredFids.listen((fid) {
      if (fid.trim().isEmpty) return;
      _registeredFid = fid;
      final waiting = _waiting;
      if (waiting != null && !waiting.isCompleted) waiting.complete(fid);
      onRegistered?.call();
    }, onError: (Object _) {
      // Sanitized diagnostics only. A later authenticated lifecycle may retry.
      debugPrint('fcm_registration_callback_failed');
      _initializing = null;
      _registeredFid = null;
    });
    await register();
  }

  Future<String> getId() async {
    try {
      await (_initializing ??= _start()).timeout(timeout);
    } catch (_) {
      _initializing = null; // A later lifecycle event may retry initialization.
      rethrow;
    }
    if (_registeredFid != null) return _registeredFid!;
    final waiting = _waiting ??= Completer<String>();
    try {
      return await waiting.future.timeout(timeout);
    } catch (_) {
      _initializing = null;
      rethrow;
    } finally {
      if (identical(_waiting, waiting)) _waiting = null;
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
