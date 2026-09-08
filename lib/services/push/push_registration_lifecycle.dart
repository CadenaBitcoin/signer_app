import 'dart:async';
import 'package:dio/dio.dart';
import 'push_registration_api.dart';

/// Only successful backend responses advance this state; never FCM callbacks.
class BackendRegistrationState {
  BackendRegistrationState(
      {this.registeredFid, Iterable<String> pending = const []})
      : pendingCleanup = pending.toSet();

  String? registeredFid;
  final Set<String> pendingCleanup;
}

/// Coordinates authenticated events; never owns or invalidates authentication.
class PushRegistrationLifecycle {
  PushRegistrationLifecycle({
    required this.readToken,
    required this.readFid,
    required this.platform,
    required this.api,
    required this.log,
    this.loadState,
    this.saveState,
    this.timeout = const Duration(seconds: 12),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final Future<String?> Function() readToken;
  final Future<String> Function() readFid;
  final String? platform;
  final PushRegistrationApi api;
  final void Function(String event) log;
  final Future<BackendRegistrationState> Function(String token)? loadState;
  final Future<void> Function(String token, BackendRegistrationState state)?
      saveState;
  final Duration timeout;
  final DateTime Function() clock;
  int _generation = 0;
  bool _disconnecting = false;
  Future<void>? _pending;
  String? _successfulToken;
  DateTime? _lastSuccess;
  String? _stateToken;
  BackendRegistrationState? _state;

  Future<BackendRegistrationState> _stateFor(String token) async {
    if (_stateToken != token || _state == null) {
      final state = await loadState?.call(token) ?? BackendRegistrationState();
      _state = state;
      _stateToken = token;
    }
    return _state!;
  }

  Future<bool> _persist(String token, BackendRegistrationState state) async {
    try {
      await saveState?.call(token, state);
      return true;
    } catch (_) {
      // Keep the confirmed state in memory; retry persistence next lifecycle.
      log('push_registration_state_save_failed');
      return false;
    }
  }

  Future<void> register({bool force = false}) {
    if (_disconnecting || platform == null) return Future<void>.value();
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
      final token = await readToken();
      if (token == null || token.isEmpty) return;
      final state = await _stateFor(token);
      if (generation != _generation || _disconnecting) return;
      final throttled = !force &&
          token == _successfulToken &&
          _lastSuccess != null &&
          clock().difference(_lastSuccess!) < const Duration(minutes: 5);
      if (!throttled) {
        final fid = await (() async {
          log('firebase_initialization_requested');
          final candidate = await readFid();
          log('firebase_fid_acquired');
          final currentToken = await readToken();
          if (generation != _generation ||
              _disconnecting ||
              cancellation.isCancelled ||
              currentToken != token) {
            return null;
          }
          await api.register(token, candidate, platform!, cancellation);
          return candidate;
        })()
            .timeout(timeout);
        if (fid == null) return;
        // Teardown drains this operation. If its in-flight POST succeeded,
        // logout must see the newly confirmed FID even if teardown has started.
        final previous = state.registeredFid;
        state.registeredFid = fid;
        if (previous != null && previous != fid) {
          state.pendingCleanup.add(previous);
        }
        state.pendingCleanup.remove(fid);
        _successfulToken = token;
        _lastSuccess = clock();
        log('push_registration_succeeded');
      }
      // Save B and the retirement of A before trying DELETE A. A failed save
      // leaves both IDs in memory and defers rotation cleanup to a later event.
      if (!await _persist(token, state)) return;
      if (generation == _generation &&
          !_disconnecting &&
          await readToken() == token) {
        await _cleanup(token, state, includeCurrent: false);
      }
    } on PushPlatformConflict {
      log('push_registration_platform_conflict');
    } catch (_) {
      log('push_registration_failed');
    } finally {
      cancellation.cancel();
    }
  }

  Future<void> _cleanup(String token, BackendRegistrationState state,
      {required bool includeCurrent}) async {
    final cancellation = CancelToken();
    // Current registration comes first on logout; retired IDs follow best-effort.
    final targets = <String>{
      if (includeCurrent && state.registeredFid != null) state.registeredFid!,
      ...state.pendingCleanup,
    };
    try {
      await (() async {
        for (final fid in targets) {
          if (cancellation.isCancelled) return;
          try {
            await api.deactivate(token, fid, cancellation);
            if (cancellation.isCancelled) return;
            if (state.registeredFid == fid) state.registeredFid = null;
            state.pendingCleanup.remove(fid);
            log('push_deregistration_succeeded');
          } catch (_) {
            log('push_deregistration_failed');
          }
        }
      })()
          .timeout(timeout);
    } catch (_) {
      log('push_deregistration_failed');
    } finally {
      cancellation.cancel();
    }
    await _persist(token, state);
  }

  /// Never acquire a candidate during teardown. Delete backend-confirmed IDs.
  Future<void> disconnect(Future<void> Function() clearSession) async {
    _disconnecting = true;
    _generation++;
    try {
      await _pending;
      final token = await readToken();
      if (token != null && token.isNotEmpty && platform != null) {
        final state = await _stateFor(token);
        await _cleanup(token, state, includeCurrent: true);
      }
    } catch (_) {
      log('push_deregistration_failed');
    } finally {
      _successfulToken = null;
      _lastSuccess = null;
      try {
        await clearSession();
      } finally {
        _state = null;
        _stateToken = null;
        _disconnecting = false;
      }
    }
  }
}
