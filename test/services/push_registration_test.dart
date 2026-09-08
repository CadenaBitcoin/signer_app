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
    final firebase = FirebaseInstallationService(
        initialize: () async {
          initializations++;
        },
        readId: () async => fid);
    expect(await firebase.getId(), fid);
    expect(await firebase.getId(), fid);
    expect(initializations, 1);
  });
  test('initialization can retry after failure without a substitute ID',
      () async {
    var attempts = 0;
    final firebase = FirebaseInstallationService(
        initialize: () async {
          if (++attempts == 1) throw StateError('unavailable');
        },
        readId: () async => fid);
    await expectLater(firebase.getId(), throwsStateError);
    expect(await firebase.getId(), fid);
  });
  test('FID acquisition failure propagates to lifecycle without fallback',
      () async {
    final firebase = FirebaseInstallationService(
        initialize: () async {},
        readId: () async => throw StateError('unavailable'));
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
        initialize: () async {}, readId: () async => ' \t');
    await expectLater(firebase.getId(), throwsStateError);
  });
  test('missing real Firebase configuration fails explicitly', () {
    expect(() => installationOptions('android'), throwsStateError);
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
    adapter.deleteStatus = 500;
    await lifecycle.disconnect(() async {
      token = null;
    });
    expect(token, isNull);
    expect(events.last, 'push_deregistration_failed');
  });
  test('repeated DELETE is safe', () async {
    await lifecycle.disconnect(() async {});
    await lifecycle.disconnect(() async {});
    expect(adapter.requests, hasLength(2));
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
  test('Firebase failure during deregistration still performs local teardown',
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
    expect(events.last, 'push_deregistration_failed');
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
