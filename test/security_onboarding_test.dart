import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signer/config/security_video.dart';
import 'package:signer/services/security_video_launcher.dart';
import 'package:signer/services/security_video_offer_store.dart';
import 'package:signer/src/ui/screens/security_help_screen.dart';
import 'package:signer/src/ui/widgets/custody_acknowledgement.dart';
import 'package:signer/src/ui/widgets/security_video_launch_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(Get.reset);

  group('security video config', () {
    test('placeholder constant is not playable', () {
      expect(kSecurityVideoUrl, contains(kSecurityVideoPlaceholderToken));
      expect(isSecurityVideoConfigured(kSecurityVideoUrl), isFalse);
    });

    test('only a complete https url is playable', () {
      expect(
        isSecurityVideoConfigured(
          'https://www.youtube-nocookie.com/embed/abcdefghijk',
        ),
        isTrue,
      );
      expect(isSecurityVideoConfigured(''), isFalse);
      expect(isSecurityVideoConfigured('   '), isFalse);
      expect(
        isSecurityVideoConfigured('http://www.youtube-nocookie.com/embed/abc'),
        isFalse,
      );
      expect(
        isSecurityVideoConfigured(
          'https://www.youtube-nocookie.com/embed/VIDEO_ID_PLACEHOLDER',
        ),
        isFalse,
      );
      expect(isSecurityVideoConfigured('not a url'), isFalse);
    });
  });

  group('security video launcher', () {
    test('does not open the placeholder', () async {
      var called = false;
      final result = await SecurityVideoLauncher(
        openUrl: (uri) async {
          called = true;
          return true;
        },
      ).open();
      expect(result, SecurityVideoLaunchResult.unavailable);
      expect(called, isFalse);
    });

    test('opens a configured https url', () async {
      Uri? seen;
      final result = await SecurityVideoLauncher(
        openUrl: (uri) async {
          seen = uri;
          return true;
        },
      ).open('https://www.youtube-nocookie.com/embed/abcdefghijk');
      expect(result, SecurityVideoLaunchResult.opened);
      expect(seen?.host, 'www.youtube-nocookie.com');
    });

    test('reports failure when the opener throws', () async {
      final result = await SecurityVideoLauncher(
        openUrl: (uri) async => throw Exception('no browser'),
      ).open('https://www.youtube-nocookie.com/embed/abcdefghijk');
      expect(result, SecurityVideoLaunchResult.failed);
    });
  });

  group('first-run offer store', () {
    test('stays unset until the offer is recorded', () async {
      final store = await SecurityVideoOfferStore.load();
      expect(store.wasOffered, isFalse);
      await store.markOffered();
      final reloaded = await SecurityVideoOfferStore.load();
      expect(reloaded.wasOffered, isTrue);
    });
  });

  group('custody acknowledgement', () {
    test('requires every statement', () {
      const empty = CustodyAcknowledgementState();
      expect(empty.allAccepted, isFalse);
      expect(
        empty.copyWith(noPasswordReset: true, responsibleForBackup: true).allAccepted,
        isFalse,
      );
      expect(
        const CustodyAcknowledgementState(
          noPasswordReset: true,
          responsibleForBackup: true,
          cadenaCannotRecover: true,
        ).allAccepted,
        isTrue,
      );
    });

    testWidgets('continue stays blocked until all three boxes are checked', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: _AcknowledgementHarness())),
      );

      final button = tester.widget<ElevatedButton>(find.byKey(const Key('continue')));
      expect(button.onPressed, isNull);

      await tester.tap(find.byKey(const Key('ack-no-password-reset')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ack-responsible-for-backup')));
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(find.byKey(const Key('continue'))).onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('ack-cadena-cannot-recover')));
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(find.byKey(const Key('continue'))).onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const Key('continue')));
      await tester.pump();
      expect(find.text('continued'), findsOneWidget);
    });
  });

  group('first-run video offer', () {
    testWidgets('skip records the offer and does not show it again', (tester) async {
      await _pumpGate(tester);
      expect(find.text('Watch now'), findsOneWidget);
      expect(find.text('Skip for now'), findsOneWidget);

      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      final store = await SecurityVideoOfferStore.load();
      expect(store.wasOffered, isTrue);
      expect(find.text('Watch now'), findsNothing);
      expect(find.text('home'), findsOneWidget);

      await _pumpGate(tester);
      expect(find.text('Watch now'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('watch now opens help and still counts as offered', (tester) async {
      await _pumpGate(tester);
      await tester.tap(find.text('Watch now'));
      await tester.pumpAndSettle();

      expect(find.text('Video not available yet'), findsOneWidget);
      expect(find.text('No password reset'), findsOneWidget);
      final store = await SecurityVideoOfferStore.load();
      expect(store.wasOffered, isTrue);
    });

    testWidgets('help screen explains the placeholder without a player', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SecurityHelpScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Self-custody and backups'), findsOneWidget);
      expect(find.text('Video not available yet'), findsOneWidget);
      expect(find.text('Play security video'), findsNothing);
      expect(find.text('Cadena cannot recover it'), findsOneWidget);
    });

    testWidgets('renders the onboarding surfaces', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(_loadScreenshotFonts);

      final acknowledgementKey = GlobalKey();
      await tester.pumpWidget(
        _shotFrame(
          acknowledgementKey,
          Scaffold(
            backgroundColor: const Color(0xff0A1123),
            appBar: AppBar(
              backgroundColor: const Color(0xff0A1123),
              foregroundColor: const Color(0xffFAF4EF),
              elevation: 0,
              title: const Text('Your Seed Phrase'),
            ),
            body: const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      'Write these words down, in order, and store them offline. You will confirm three of them next.',
                      style: TextStyle(color: Color(0xffFFB950), fontSize: 13, height: 1.35),
                    ),
                    SizedBox(height: 12),
                    Expanded(
                      child: _AcknowledgementHarness(buttonLabel: 'Verify Seed Phrase'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _saveShot(tester, acknowledgementKey, 'acknowledgement');

      Get.reset();
      final helpKey = GlobalKey();
      await tester.pumpWidget(
        _shotFrame(helpKey, const SecurityHelpScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Video not available yet'), findsOneWidget);
      expect(find.text('Watch now'), findsNothing);
      await _saveShot(tester, helpKey, 'security-help');

      Get.reset();
      SharedPreferences.setMockInitialValues({});
      final offerKey = GlobalKey();
      await tester.pumpWidget(
        _shotFrame(
          offerKey,
          const SecurityVideoLaunchGate(
            child: Scaffold(
              backgroundColor: Color(0xff0A1123),
              body: SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Watch now'), findsOneWidget);
      await _saveShot(tester, offerKey, 'video-offer');
    });
  });
}

Future<void> _pumpGate(WidgetTester tester) async {
  await tester.pumpWidget(
    const GetMaterialApp(
      home: SecurityVideoLaunchGate(
        child: Scaffold(body: Text('home')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _AcknowledgementHarness extends StatefulWidget {
  final String buttonLabel;

  const _AcknowledgementHarness({this.buttonLabel = 'Continue'});

  @override
  State<_AcknowledgementHarness> createState() => _AcknowledgementHarnessState();
}

class _AcknowledgementHarnessState extends State<_AcknowledgementHarness> {
  CustodyAcknowledgementState _value = const CustodyAcknowledgementState();
  bool _continued = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CustodyAcknowledgement(
          value: _value,
          onChanged: (next) => setState(() => _value = next),
        ),
        ElevatedButton(
          key: const Key('continue'),
          onPressed: _value.allAccepted ? () => setState(() => _continued = true) : null,
          child: Text(widget.buttonLabel),
        ),
        if (_continued) const Text('continued'),
      ],
    );
  }
}

Widget _shotFrame(GlobalKey key, Widget home) {
  return GetMaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'Roboto'),
    builder: (context, child) => RepaintBoundary(
      key: key,
      child: child ?? const SizedBox.shrink(),
    ),
    home: home,
  );
}

Future<void> _loadScreenshotFonts() async {
  const save = bool.fromEnvironment('SAVE_SCREENSHOTS');
  if (!save) return;
  final fontsDir = _materialFontsDir();
  if (fontsDir == null) return;
  await _loadFont('Roboto', '$fontsDir/Roboto-Regular.ttf');
  await _loadFont('Roboto', '$fontsDir/Roboto-Medium.ttf');
  await _loadFont('Roboto', '$fontsDir/Roboto-Bold.ttf');
  await _loadFont('MaterialIcons', '$fontsDir/MaterialIcons-Regular.otf');
}

String? _materialFontsDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 10; i++) {
    final direct = Directory('${dir.path}/material_fonts');
    if (direct.existsSync()) return direct.path;
    final nested = Directory('${dir.path}/bin/cache/artifacts/material_fonts');
    if (nested.existsSync()) return nested.path;
    if (dir.path == dir.parent.path) break;
    dir = dir.parent;
  }
  return null;
}

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final bytes = await file.readAsBytes();
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _saveShot(WidgetTester tester, GlobalKey key, String name) async {
  const save = bool.fromEnvironment('SAVE_SCREENSHOTS');
  if (!save) return;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('/tmp/security_onboarding/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}
