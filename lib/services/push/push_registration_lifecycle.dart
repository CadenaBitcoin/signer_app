import 'dart:async';
import 'package:dio/dio.dart';
import 'push_registration_api.dart';

/// Coordinates authenticated events; never owns or invalidates authentication.
class PushRegistrationLifecycle {
  PushRegistrationLifecycle({
    required this.readToken,
    required this.readFid,
    required this.platform,
    required this.api,
    required this.log,
    this.timeout = const Duration(seconds: 12),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final Future<String?> Function() readToken;
  final Future<String> Function() readFid;
  final String? platform;
  final PushRegistrationApi api;
  final void Function(String event) log;
  final Duration timeout;
  final DateTime Function() clock;
  int _generation = 0;
  bool _disconnecting = false;
  Future<void>? _pending;
  String? _successfulToken;
  DateTime? _lastSuccess;

  Future<void> register({bool force = false}) {
    if (_disconnecting || platform == null) return Future<void>.value();
    // Serialize events so a token change during FID acquisition gets its own turn.
    final previous = _pending;
    final generation = _generation;
    final operation = (() async {
      if (previous != null) await previous;
      if (_disconnecting || generation != _generation) return;
      await _register(generation, force);
    })();
    _pending = operation;
    return operation.whenComplete(() {
      if (identical(_pending, operation)) _pending = null;
    });
  }

  Future<void> _register(int generation, bool force) async {
    final cancellation = CancelToken();
    try {
      await (() async {
        final token = await readToken();
        if (token == null || token.isEmpty) return;
        if (!force &&
            token == _successfulToken &&
            _lastSuccess != null &&
            clock().difference(_lastSuccess!) < const Duration(minutes: 5)) {
          return;
        }
        log('firebase_initialization_requested');
        final fid = await readFid();
        log('firebase_fid_acquired');
        if (generation != _generation ||
            _disconnecting ||
            cancellation.isCancelled ||
            await readToken() != token) {
          return;
        }
        await api.register(token, fid, platform!, cancellation);
        _successfulToken = token;
        _lastSuccess = clock();
        log('push_registration_succeeded');
      })()
          .timeout(timeout);
    } on PushPlatformConflict {
      log('push_registration_platform_conflict');
    } catch (_) {
      // Never log exception/request objects: they may contain credentials/FIDs.
      log('push_registration_failed');
    } finally {
      cancellation.cancel();
    }
  }

  /// Stops new registration, drains the bounded in-flight operation, then
  /// attempts DELETE before invoking local teardown, even on failure.
  Future<void> disconnect(Future<void> Function() clearSession) async {
    _disconnecting = true;
    _generation++;
    final cancellation = CancelToken();
    try {
      await _pending;
      await (() async {
        final token = await readToken();
        if (token == null || token.isEmpty || platform == null) return;
        final fid = await readFid();
        if (cancellation.isCancelled) return;
        await api.deactivate(token, fid, cancellation);
        log('push_deregistration_succeeded');
      })()
          .timeout(timeout);
    } catch (_) {
      log('push_deregistration_failed');
    } finally {
      cancellation.cancel();
      _successfulToken = null;
      _lastSuccess = null;
      try {
        await clearSession();
      } finally {
        _disconnecting = false;
      }
    }
  }
}
