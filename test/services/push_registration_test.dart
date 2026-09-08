import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signer/services/push/firebase_installation_service.dart';
import 'package:signer/services/push/push_registration_api.dart';
import 'package:signer/services/push/push_registration_lifecycle.dart';
import 'package:signer/services/push/push_registration_runtime.dart';
import 'package:signer/services/storage_service.dart';
import 'package:signer/services/secure_storage_service.dart';

class RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int postStatus = 200;
  int deleteStatus = 204;
  bool fail = false;
  Future<void> Function(RequestOptions)? beforeResponse;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    await beforeResponse?.call(options);
    if (fail) throw StateError('network unavailable');
    return ResponseBody.fromString(
        '', options.method == 'POST' ? postStatus : deleteStatus);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingAdapter adapter;
  late PushRegistrationApi api;
  late PushRegistrationLifecycle lifecycle;
  late List<String> events;
  String? token;
  String fid = ' Opaque/FID+AbC ';
  late DateTime now;
  final secure = <String, String>{};
  String jwt() => 'header.${base64Url.encode(utf8.encode(jsonEncode({
            'exp': DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch ~/
                1000,
            'sub': 'authenticated-user',
          })))}.signature';

  setUp(() {
    fid = ' Opaque/FID+AbC ';
    adapter = RecordingAdapter();
    api = PushRegistrationApi('https://staging.invalid/app',
        dio: Dio()..httpClientAdapter = adapter);
    token = 'current-jwt';
    events = [];
    now = DateTime(2026);
    lifecycle = PushRegistrationLifecycle(
      readToken: () async => token,
      readFid: () async => fid,
      platform: 'android',
      api: api,
      log: events.add,
      clock: () => now,
    );
    secure.clear();
    SharedPreferences.setMockInitialValues({});
    PushRegistrationRuntime.lifecycle = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'read':
          return secure[args!['key']];
        case 'write':
          secure[args!['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          secure.remove(args!['key']);
          return null;
        case 'deleteAll':
          secure.clear();
          return null;
        case 'readAll':
          return Map<String, String>.of(secure);
      }
      return null;
    });
  });

  test('Firebase returns its exact ID and initializes once', () async {
    var initializations = 0;
    final registered = StreamController<String>.broadcast();
    addTearDown(registered.close);
    final firebase = FirebaseInstallationService(
        initialize: () async {
          initializations++;
        },
        register: () async => registered.add(fid),
        registeredFids: registered.stream);
    addTearDown(firebase.dispose);
    expect(await firebase.getId(), fid);
    expect(await firebase.getId(), fid);
    expect(initializations, 1);
  });
  test('initialization can retry after failure without a substitute ID',
      () async {
    var attempts = 0;
    final registered = StreamController<String>.broadcast();
    addTearDown(registered.close);
    final firebase = FirebaseInstallationService(
        initialize: () async {
          if (++attempts == 1) throw StateError('unavailable');
        },
        register: () async => registered.add(fid),
        registeredFids: registered.stream);
    addTearDown(firebase.dispose);
    await expectLater(firebase.getId(), throwsStateError);
    expect(await firebase.getId(), fid);
  });
  test('FID acquisition failure propagates to lifecycle without fallback',
      () async {
    final firebase = FirebaseInstallationService(
        initialize: () async {},
        register: () async => throw StateError('unavailable'),
        registeredFids: const Stream.empty());
    addTearDown(firebase.dispose);
    final service = PushRegistrationLifecycle(
        readToken: () async => token,
        readFid: firebase.getId,
        platform: 'android',
        api: api,
        log: events.add);
    await service.register();
    expect(adapter.requests, isEmpty);
    expect(token, 'current-jwt');
    expect(events, contains('push_registration_failed'));
  });
  test('empty Firebase ID is rejected', () async {
    final firebase = FirebaseInstallationService(
        initialize: () async {},
        register: () async {},
        registeredFids: Stream.value(' \t'),
        timeout: const Duration(milliseconds: 10));
    addTearDown(firebase.dispose);
    await expectLater(firebase.getId(), throwsA(isA<TimeoutException>()));
  });
  test('Android initialization uses native Google Services resources', () {
    expect(installationOptions('android'), isNull);
  });
  test('FCM register success alone does not supply an uploadable FID',
      () async {
    final service = FirebaseInstallationService(
        initialize: () async {},
        register: () async {},
        registeredFids: const Stream.empty(),
        timeout: const Duration(milliseconds: 10));
    addTearDown(service.dispose);
    final orchestration = PushRegistrationLifecycle(
        readToken: () async => token,
        readFid: service.getId,
        platform: 'android',
        api: api,
        log: events.add);
    await orchestration.register();
    expect(adapter.requests, isEmpty);
    expect(token, 'current-jwt');
  });
  test(
      'late registered-FID callback retries after timeout and forwards rotation',
      () async {
    final registered = StreamController<String>.broadcast();
    addTearDown(registered.close);
    late PushRegistrationLifecycle orchestration;
    final service = FirebaseInstallationService(
        initialize: () async {},
        register: () async {},
        registeredFids: registered.stream,
        timeout: const Duration(milliseconds: 10),
        onRegistered: () => unawaited(orchestration.register(force: true)));
    addTearDown(service.dispose);
    orchestration = PushRegistrationLifecycle(
        readToken: () async => token,
        readFid: service.getId,
        platform: 'android',
        api: api,
        log: events.add);
    await orchestration.register();
    expect(adapter.requests, isEmpty);
    registered.add(' Confirmed-FCM-ID ');
    await Future<void>.delayed(Duration.zero);
    await orchestration.register();
    expect(adapter.requests.last.data['firebase_installation_id'],
        ' Confirmed-FCM-ID ');
    registered.add('Rotated-FCM-ID');
    await Future<void>.delayed(Duration.zero);
    await orchestration.register();
    expect(
        adapter.requests
            .lastWhere((r) => r.method == 'POST')
            .data['firebase_installation_id'],
        'Rotated-FCM-ID');
  });
  test('FCM events do not register an unauthenticated user or resurrect logout',
      () async {
    final registered = StreamController<String>.broadcast();
    addTearDown(registered.close);
    final service = FirebaseInstallationService(
        initialize: () async {},
        register: () async => registered.add(fid),
        registeredFids: registered.stream,
        onRegistered: () => PushRegistrationRuntime.authenticated(force: true));
    addTearDown(service.dispose);
    PushRegistrationRuntime.lifecycle = PushRegistrationLifecycle(
        readToken: () async => token,
        readFid: service.getId,
        platform: 'android',
        api: api,
        log: events.add);
    token = null;
    await service.getId();
    await PushRegistrationRuntime.lifecycle!.register();
    expect(adapter.requests, isEmpty);
    token = 'current-jwt';
    await PushRegistrationRuntime.lifecycle!.register();
    await PushRegistrationRuntime.disconnect(() async {
      token = null;
    });
    final count = adapter.requests.length;
    registered.add('Post-logout-FCM-ID');
    await Future<void>.delayed(Duration.zero);
    await PushRegistrationRuntime.lifecycle!.register();
    expect(adapter.requests.length, count);
    expect(adapter.requests.last.method, 'DELETE');
  });
  test('service disposal detaches the registered-FID listener', () async {
    final registered = StreamController<String>.broadcast();
    addTearDown(registered.close);
    var callbacks = 0;
    final service = FirebaseInstallationService(
        initialize: () async {},
        register: () async => registered.add(fid),
        registeredFids: registered.stream,
        onRegistered: () {
          callbacks++;
        });
    await service.getId();
    await service.dispose();
    final before = callbacks;
    registered.add('Later');
    await Future<void>.delayed(Duration.zero);
    expect(callbacks, before);
  });
  test('missing iOS Firebase configuration fails explicitly', () {
    expect(() => installationOptions('ios'), throwsStateError);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('platform maps ${platform.name}', () {
      expect(installationPlatform(platform),
          platform == TargetPlatform.android ? 'android' : 'ios');
    });
  }
  test('unsupported targets do not pretend to be a mobile OS', () {
    expect(installationPlatform(TargetPlatform.linux), isNull);
    expect(installationPlatform(TargetPlatform.android, web: true), isNull);
  });
  test('POST sends only exact FID and platform with current bearer token',
      () async {
    await lifecycle.register();
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/app/auth/push-registration');
    expect(
        request.data, {'firebase_installation_id': fid, 'platform': 'android'});
    expect(request.headers['Authorization'], 'Bearer current-jwt');
    expect(events, contains('push_registration_succeeded'));
    expect(
        events.any(
            (event) => event.contains(fid) || event.contains('current-jwt')),
        isFalse);
  });
  test('iOS is sent unchanged', () async {
    await api.register('jwt', fid, 'ios', CancelToken());
    expect(adapter.requests.single.data['platform'], 'ios');
  });
  test('unauthenticated startup never acquires FID or posts', () async {
    token = null;
    await lifecycle.register();
    expect(adapter.requests, isEmpty);
    expect(events, isEmpty);
  });
  test('repeated registration succeeds and resume is throttled', () async {
    await lifecycle.register();
    await lifecycle.register();
    expect(adapter.requests, hasLength(1));
    now = now.add(const Duration(minutes: 6));
    await lifecycle.register();
    expect(adapter.requests, hasLength(2));
  });
  test('new authenticated token registers despite previous success', () async {
    await lifecycle.register();
    token = 'new-user-jwt';
    await lifecycle.register();
    expect(
        adapter.requests.last.headers['Authorization'], 'Bearer new-user-jwt');
    expect(adapter.requests, hasLength(2));
  });
  for (final status in [409, 500, 401, 422]) {
    test('POST $status is nonfatal and retryable on next lifecycle event',
        () async {
      adapter.postStatus = status;
      await lifecycle.register();
      expect(token, 'current-jwt');
      expect(
          events,
          contains(status == 409
              ? 'push_registration_platform_conflict'
              : 'push_registration_failed'));
      adapter.postStatus = 200;
      await lifecycle.register();
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.last.data['platform'], 'android');
    });
  }
  test('network failure is nonfatal without exposing request details',
      () async {
    adapter.fail = true;
    await lifecycle.register();
    expect(token, 'current-jwt');
    expect(events.last, 'push_registration_failed');
  });
  test('DELETE targets encoded exact FID, handles empty 204 before teardown',
      () async {
    await lifecycle.register();
    adapter.requests.clear();
    adapter.beforeResponse = (request) async {
      expect(token, 'current-jwt');
    };
    await lifecycle.disconnect(() async {
      token = null;
    });
    final request = adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path, endsWith(Uri.encodeComponent(fid)));
    expect(request.headers['Authorization'], 'Bearer current-jwt');
    expect(token, isNull);
    expect(events, contains('push_deregistration_succeeded'));
  });
  test('DELETE failure still clears session', () async {
    await lifecycle.register();
    adapter.deleteStatus = 500;
    await lifecycle.disconnect(() async {
      token = null;
    });
    expect(token, isNull);
    expect(events.last, 'push_deregistration_failed');
  });
  test('repeated DELETE is safe', () async {
    await lifecycle.register();
    await lifecycle.disconnect(() async {});
    await lifecycle.disconnect(() async {});
    expect(adapter.requests.map((r) => r.method), ['POST', 'DELETE']);
  });
  test('slow FID cannot register after logout', () async {
    final fidReady = Completer<String>();
    final service = PushRegistrationLifecycle(
        readToken: () async => token,
        readFid: () => fidReady.future,
        platform: 'android',
        api: api,
        log: events.add,
        timeout: const Duration(milliseconds: 10));
    final registration = service.register();
    await Future<void>.delayed(Duration.zero);
    await service.disconnect(() async {
      token = null;
    });
    fidReady.complete(fid);
    await registration;
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requests, isEmpty);
    expect(token, isNull);
  });
  test('in-flight POST finishes before logout DELETE', () async {
    final response = Completer<void>();
    final started = Completer<void>();
    adapter.beforeResponse = (request) async {
      if (request.method == 'POST') {
        started.complete();
        await response.future;
      }
    };
    final registration = lifecycle.register();
    await started.future;
    final logout = lifecycle.disconnect(() async {
      token = null;
    });
    response.complete();
    await Future.wait([registration, logout]);
    expect(adapter.requests.map((r) => r.method), ['POST', 'DELETE']);
    expect(token, isNull);
  });

  test('concurrent resume events coalesce after first successful registration',
      () async {
    await Future.wait(List.generate(5, (_) => lifecycle.register()));
    expect(adapter.requests, hasLength(1));
  });

  test('rotation confirms B before retiring A, then logout deletes B',
      () async {
    fid = 'A';
    await lifecycle.register();
    fid = 'B';
    await lifecycle.register(force: true);
    expect(adapter.requests.map((r) => r.method), ['POST', 'POST', 'DELETE']);
    expect(adapter.requests[1].data['firebase_installation_id'], 'B');
    expect(adapter.requests[2].path, endsWith('/A'));
    await lifecycle.disconnect(() async {
      token = null;
    });
    expect(adapter.requests.last.path, endsWith('/B'));
  });

  test('failed POST B preserves A and never prematurely deletes A', () async {
    fid = 'A';
    await lifecycle.register();
    fid = 'B';
    adapter.postStatus = 500;
    await lifecycle.register(force: true);
    expect(adapter.requests.map((r) => r.method), ['POST', 'POST']);
    await lifecycle.disconnect(() async {
      token = null;
    });
    expect(adapter.requests.last.path, endsWith('/A'));
  });

  test('logout during candidate acquisition deletes A and prevents POST B',
      () async {
    final candidateReady = Completer<String>();
    final acquiring = Completer<void>();
    var rotating = false;
    final service = PushRegistrationLifecycle(
      readToken: () async => token,
      readFid: () {
        if (!rotating) return Future.value('A');
        acquiring.complete();
        return candidateReady.future;
      },
      platform: 'android',
      api: api,
      log: events.add,
    );
    await service.register();
    rotating = true;
    final rotation = service.register(force: true);
    await acquiring.future;
    final logout = service.disconnect(() async {
      token = null;
    });
    candidateReady.complete('B');
    await Future.wait([rotation, logout]);
    await service.register(force: true);
    expect(adapter.requests.map((r) => r.method), ['POST', 'DELETE']);
    expect(adapter.requests.last.path, endsWith('/A'));
  });

  for (final succeeds in [false, true]) {
    test('logout drains in-flight rotation, POST B succeeds=$succeeds',
        () async {
      fid = 'A';
      await lifecycle.register();
      fid = 'B';
      final started = Completer<void>();
      final finish = Completer<void>();
      adapter.postStatus = succeeds ? 200 : 500;
      adapter.beforeResponse = (request) async {
        if (request.method == 'POST') {
          started.complete();
          await finish.future;
        }
      };
      final rotation = lifecycle.register(force: true);
      await started.future;
      final logout = lifecycle.disconnect(() async {
        token = null;
      });
      finish.complete();
      await Future.wait([rotation, logout]);
      final deletions =
          adapter.requests.where((r) => r.method == 'DELETE').toList();
      expect(deletions.first.path, endsWith(succeeds ? '/B' : '/A'));
      if (succeeds) expect(deletions.last.path, endsWith('/A'));
    });
  }

  test('failed retirement is nonfatal and retries even during POST throttle',
      () async {
    fid = 'A';
    await lifecycle.register();
    fid = 'B';
    adapter.deleteStatus = 500;
    await lifecycle.register(force: true);
    expect(events, contains('push_registration_succeeded'));
    expect(token, 'current-jwt');
    adapter.deleteStatus = 204;
    await lifecycle.register();
    expect(adapter.requests.map((r) => r.method),
        ['POST', 'POST', 'DELETE', 'DELETE']);
    expect(adapter.requests.last.path, endsWith('/A'));
    await lifecycle.disconnect(() async {
      token = null;
    });
    expect(adapter.requests.last.path, endsWith('/B'));
  });

  PushRegistrationLifecycle persistedLifecycle(String baseUrl,
          {Future<String> Function()? candidate}) =>
      PushRegistrationLifecycle(
        readToken: () async => token,
        readFid: candidate ?? (() async => fid),
        platform: 'android',
        api: api,
        log: events.add,
        loadState: (jwt) =>
            PushRegistrationRuntime.loadRegistrationState(baseUrl, jwt),
        saveState: (jwt, state) =>
            PushRegistrationRuntime.saveRegistrationState(baseUrl, jwt, state),
      );

  test(
      'restart and JWT refresh retain confirmed A without a candidate callback',
      () async {
    const baseUrl = 'https://staging.invalid/app';
    token = jwt();
    fid = 'A';
    await persistedLifecycle(baseUrl).register();
    token =
        '${token!}refreshed'; // Same authenticated subject, different JWT bytes.
    final restarted = persistedLifecycle(baseUrl,
        candidate: () async => throw StateError('no FCM callback'));
    await restarted.disconnect(() async {
      token = null;
    });
    expect(adapter.requests.last.path, endsWith('/A'));
    expect(secure, isEmpty);
  });

  test('confirmed state is isolated by backend and authenticated subject',
      () async {
    const baseUrl = 'https://staging.invalid/app';
    final firstToken = jwt();
    token = firstToken;
    fid = 'A';
    await persistedLifecycle(baseUrl).register();
    await persistedLifecycle('https://production.invalid/app')
        .disconnect(() async {});
    final otherClaims = base64Url.encode(utf8.encode(jsonEncode({
      'sub': 'another-user',
      'exp': 9999999999,
    })));
    token = 'header.$otherClaims.signature';
    await persistedLifecycle(baseUrl).disconnect(() async {});
    expect(adapter.requests, hasLength(1));
    token = firstToken;
    await persistedLifecycle(baseUrl).disconnect(() async {});
    expect(adapter.requests.last.path, endsWith('/A'));
  });

  test('pending rotation cleanup survives restart and does not delete active B',
      () async {
    const baseUrl = 'https://staging.invalid/app';
    token = jwt();
    final service = persistedLifecycle(baseUrl);
    fid = 'A';
    await service.register();
    fid = 'B';
    adapter.deleteStatus = 500;
    await service.register(force: true);
    final stored =
        await PushRegistrationRuntime.loadRegistrationState(baseUrl, token!);
    expect(stored.registeredFid, 'B');
    expect(stored.pendingCleanup, {'A'});
    adapter.deleteStatus = 204;
    await persistedLifecycle(baseUrl).disconnect(() async {
      token = null;
    });
    final deletions =
        adapter.requests.where((r) => r.method == 'DELETE').toList();
    expect(deletions[deletions.length - 2].path, endsWith('/B'));
    expect(deletions.last.path, endsWith('/A'));
    expect(secure, isEmpty);
  });

  test('B is durably authoritative before DELETE A is attempted', () async {
    const baseUrl = 'https://staging.invalid/app';
    token = jwt();
    final service = persistedLifecycle(baseUrl);
    fid = 'A';
    await service.register();
    adapter.beforeResponse = (request) async {
      final state =
          await PushRegistrationRuntime.loadRegistrationState(baseUrl, token!);
      if (request.method == 'POST') {
        expect(state.registeredFid, 'A');
      } else {
        expect(state.registeredFid, 'B');
        expect(state.pendingCleanup, {'A'});
      }
    };
    fid = 'B';
    await service.register(force: true);
  });

  test('failed logout deletion survives logout and retries after login',
      () async {
    const baseUrl = 'https://staging.invalid/app';
    final credential = jwt();
    token = credential;
    fid = 'A';
    final service = persistedLifecycle(baseUrl);
    await service.register();
    adapter.deleteStatus = 500;
    await service.disconnect(() async {
      token = null;
    });
    expect(
        (await PushRegistrationRuntime.loadRegistrationState(
                baseUrl, credential))
            .registeredFid,
        'A');
    adapter.deleteStatus = 204;
    token = credential;
    fid = 'B';
    await persistedLifecycle(baseUrl).register();
    expect(adapter.requests.last.method, 'DELETE');
    expect(adapter.requests.last.path, endsWith('/A'));
    expect(
        (await PushRegistrationRuntime.loadRegistrationState(
                baseUrl, credential))
            .registeredFid,
        'B');
  });

  test('state save failure does not undo POST B or lose its logout target',
      () async {
    var failSave = false;
    final service = PushRegistrationLifecycle(
      readToken: () async => token,
      readFid: () async => fid,
      platform: 'android',
      api: api,
      log: events.add,
      saveState: (_, __) async {
        if (failSave) throw StateError('storage failed');
      },
    );
    fid = 'A';
    await service.register();
    fid = 'B';
    failSave = true;
    await service.register(force: true);
    expect(adapter.requests.map((r) => r.method), ['POST', 'POST']);
    expect(events, contains('push_registration_state_save_failed'));
    await service.disconnect(() async {
      token = null;
    });
    final deletions =
        adapter.requests.where((r) => r.method == 'DELETE').toList();
    expect(deletions.first.path, endsWith('/B'));
    expect(deletions.last.path, endsWith('/A'));
  });
  test(
      'session changed during FID acquisition is not posted with old credentials',
      () async {
    final ready = Completer<String>();
    final acquired = Completer<void>();
    final service = PushRegistrationLifecycle(
        readToken: () async => token,
        readFid: () {
          acquired.complete();
          return ready.future;
        },
        platform: 'android',
        api: api,
        log: events.add);
    final registration = service.register();
    await acquired.future;
    token = 'replacement-user';
    ready.complete(fid);
    await registration;
    expect(adapter.requests, isEmpty);
  });
  test('logout without backend-confirmed FID never acquires a candidate',
      () async {
    final service = PushRegistrationLifecycle(
        readToken: () async => token,
        readFid: () async => throw StateError('unavailable'),
        platform: 'ios',
        api: api,
        log: events.add);
    await service.disconnect(() async {
      token = null;
    });
    expect(token, isNull);
    expect(adapter.requests, isEmpty);
    expect(events, isEmpty);
  });
  test('unsupported platform performs neither Firebase nor network work',
      () async {
    final service = PushRegistrationLifecycle(
        readToken: () async => token,
        readFid: () async => throw StateError('must not acquire'),
        platform: null,
        api: api,
        log: events.add);
    await service.register();
    await service.disconnect(() async {});
    expect(events, isEmpty);
    expect(adapter.requests, isEmpty);
  });

  Future<void> configureRuntime() async {
    secure['isLoggedIn'] = 'true';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwtToken', jwt());
    PushRegistrationRuntime.lifecycle = PushRegistrationLifecycle(
        readToken: PushRegistrationRuntime.authenticatedToken,
        readFid: () async => fid,
        platform: 'android',
        api: api,
        log: events.add);
  }

  test('successful token persistence triggers authenticated registration',
      () async {
    await configureRuntime();
    expect(
        await PushRegistrationRuntime.persistToken(
            jwt(), PushRegistrationRuntime.sessionGeneration),
        isTrue);
    await PushRegistrationRuntime.lifecycle!.register();
    expect(adapter.requests, hasLength(1));
  });
  test('registration failure leaves persisted authentication intact', () async {
    await configureRuntime();
    adapter.fail = true;
    final credential = jwt();
    expect(
        await PushRegistrationRuntime.persistToken(
            credential, PushRegistrationRuntime.sessionGeneration),
        isTrue);
    await PushRegistrationRuntime.lifecycle!.register();
    expect((await SharedPreferences.getInstance()).getString('jwtToken'),
        credential);
    expect(secure['isLoggedIn'], 'true');
  });
  test('logged-out restored app does not register a retained JWT', () async {
    await configureRuntime();
    secure['isLoggedIn'] = 'false';
    PushRegistrationRuntime.authenticated();
    await PushRegistrationRuntime.lifecycle!.register();
    expect(adapter.requests, isEmpty);
  });
  test('restored authenticated session registers', () async {
    await configureRuntime();
    PushRegistrationRuntime.authenticated();
    await PushRegistrationRuntime.lifecycle!.register();
    expect(adapter.requests, hasLength(1));
  });
  test('local unlock triggers registration with existing valid backend JWT',
      () async {
    await configureRuntime();
    secure['isLoggedIn'] = 'false';
    await StorageService.setLoginStatus(true);
    await PushRegistrationRuntime.lifecycle!.register();
    expect(adapter.requests, hasLength(1));
  });
  test('expired and malformed JWTs do not register at startup', () async {
    await configureRuntime();
    final prefs = await SharedPreferences.getInstance();
    for (final invalid in [
      'bad',
      'h.${base64Url.encode(utf8.encode('{"exp":1}'))}.s'
    ]) {
      await prefs.setString('jwtToken', invalid);
      expect(await PushRegistrationRuntime.authenticatedToken(), isNull);
    }
  });
  for (final reset in ['logout', 'reset', 'clearUsers', 'secureReset']) {
    for (final failure in [false, true]) {
      test('$reset attempts DELETE before clearing auth, failure=$failure',
          () async {
        await configureRuntime();
        await PushRegistrationRuntime.lifecycle!.register();
        adapter.requests.clear();
        adapter.fail = failure;
        final prefs = await SharedPreferences.getInstance();
        adapter.beforeResponse = (request) async {
          expect(prefs.getString('jwtToken'), isNotNull);
          expect(secure['isLoggedIn'], 'true');
        };
        switch (reset) {
          case 'logout':
            await StorageService.logoutUser();
          case 'reset':
            await StorageService.resetUserData();
          case 'clearUsers':
            await StorageService.clearAllUsers();
          case 'secureReset':
            await SecureStorageService().forceReset();
        }
        expect(adapter.requests.single.method, 'DELETE');
        expect(prefs.getString('jwtToken'), isNull);
        expect(secure['isLoggedIn'], isNot('true'));
      });
    }
  }
  test('late authentication response cannot restore session after logout',
      () async {
    await configureRuntime();
    final generation = PushRegistrationRuntime.sessionGeneration;
    await StorageService.logoutUser();
    expect(
        await PushRegistrationRuntime.persistToken(jwt(), generation), isFalse);
    expect(
        (await SharedPreferences.getInstance()).getString('jwtToken'), isNull);
  });
}
