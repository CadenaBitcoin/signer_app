import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signer/services/installed_app_info.dart';
import 'package:signer/src/ui/widgets/app_version_label.dart';

const _installed = InstalledAppInfo(version: '1.0.4', buildNumber: '1000035');

Widget _host({
  InstalledAppInfo? installed = _installed,
  num? apiVersion,
  String? newest,
  String environment = 'production',
}) {
  return MaterialApp(
    home: Scaffold(
      body: AppVersionLabel(
        installed: installed,
        apiVersion: apiVersion,
        newestPublished: newest,
        environment: environment,
      ),
    ),
  );
}

String _line(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('app-version-line'))).data!;

void main() {
  group('installed version display', () {
    testWidgets('shows the installed version, build number and API version',
        (tester) async {
      await tester.pumpWidget(_host(apiVersion: 6));
      expect(_line(tester), 'App: 1.0.4 (1000035) | API: 6');
    });

    testWidgets('shows a fractional API version as reported', (tester) async {
      await tester.pumpWidget(_host(apiVersion: 0.0));
      expect(_line(tester), 'App: 1.0.4 (1000035) | API: 0.0');
    });

    testWidgets('keeps the build number out of the product version',
        (tester) async {
      await tester.pumpWidget(_host(
        installed: const InstalledAppInfo(version: '1.0.5', buildNumber: '1000036'),
      ));
      expect(_line(tester), startsWith('App: 1.0.5 (1000036)'));
    });

    testWidgets('omits the parentheses when there is no build number',
        (tester) async {
      await tester.pumpWidget(_host(
        installed: const InstalledAppInfo(version: '1.0.4', buildNumber: ''),
      ));
      expect(_line(tester), 'App: 1.0.4 | API: N/A');
    });
  });

  group('independence from the backend', () {
    testWidgets('the installed version stays visible without backend data',
        (tester) async {
      await tester.pumpWidget(_host(apiVersion: null, newest: null));
      expect(_line(tester), 'App: 1.0.4 (1000035) | API: N/A');
      expect(find.byKey(const Key('app-newest-published')), findsNothing);
    });

    testWidgets('a different backend "newest" never replaces the installed version',
        (tester) async {
      await tester.pumpWidget(_host(apiVersion: 6, newest: '9.9.9'));
      expect(_line(tester), 'App: 1.0.4 (1000035) | API: 6');
      expect(_line(tester), isNot(contains('9.9.9')));
    });

    testWidgets('the backend newest version appears only under its own label',
        (tester) async {
      await tester.pumpWidget(_host(apiVersion: 6, newest: '1.0.5'));
      final newest = tester.widget<Text>(find.byKey(const Key('app-newest-published')));
      expect(newest.data, 'Newest published: 1.0.5');
    });

    testWidgets('the API version is shown as reported, whatever the installed version',
        (tester) async {
      await tester.pumpWidget(_host(apiVersion: 7));
      expect(_line(tester), endsWith('| API: 7'));
      await tester.pumpWidget(_host(
        installed: const InstalledAppInfo(version: '2.0.0', buildNumber: '2000001'),
        apiVersion: 7,
      ));
      expect(_line(tester), 'App: 2.0.0 (2000001) | API: 7');
    });

    testWidgets('an empty backend value shows no "newest" line', (tester) async {
      await tester.pumpWidget(_host(newest: '  '));
      expect(find.byKey(const Key('app-newest-published')), findsNothing);
    });
  });

  group('package information unavailable', () {
    testWidgets('says unavailable and never falls back to the backend value',
        (tester) async {
      await tester.pumpWidget(_host(installed: null, apiVersion: 6, newest: '1.0.5'));
      expect(_line(tester), 'App: unavailable | API: 6');
      // The backend value is still shown, but only under its own label.
      expect(find.text('Newest published: 1.0.5'), findsOneWidget);
    });

    testWidgets('both sources unavailable', (tester) async {
      await tester.pumpWidget(_host(installed: null));
      expect(_line(tester), 'App: unavailable | API: N/A');
    });
  });

  group('staging versus production', () {
    testWidgets('staging shows a separate STAGING marker, not part of the version',
        (tester) async {
      await tester.pumpWidget(_host(environment: 'staging', apiVersion: 6));
      expect(find.byKey(const Key('app-environment-marker')), findsOneWidget);
      expect(find.text('STAGING'), findsOneWidget);
      expect(_line(tester), 'App: 1.0.4 (1000035) | API: 6');
      expect(_line(tester), isNot(contains('STAGING')));
    });

    testWidgets('production shows no environment marker', (tester) async {
      await tester.pumpWidget(_host(environment: 'production', apiVersion: 6));
      expect(find.byKey(const Key('app-environment-marker')), findsNothing);
      expect(find.textContaining('STAGING'), findsNothing);
    });

    testWidgets('the same installed version reads identically in both environments',
        (tester) async {
      await tester.pumpWidget(_host(environment: 'staging', apiVersion: 6));
      final staging = _line(tester);
      await tester.pumpWidget(_host(environment: 'production', apiVersion: 6));
      expect(_line(tester), staging);
    });
  });

  group('no hard-coded version', () {
    test('the version display code contains no literal product version', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)',
              multiLine: true)
          .firstMatch(pubspec);
      expect(match, isNotNull, reason: 'pubspec.yaml version: line');
      final name = match!.group(1)!;
      final build = match.group(2)!;
      for (final path in [
        'lib/services/installed_app_info.dart',
        'lib/src/ui/widgets/app_version_label.dart',
        'lib/src/ui/screens/HomeScreen.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source.contains(name), isFalse, reason: '$path contains $name');
        expect(source.contains(build), isFalse, reason: '$path contains $build');
      }
    });

    test('the Dashboard App value does not come from the backend model', () {
      final home = File('lib/src/ui/screens/HomeScreen.dart').readAsStringSync();
      final start = home.indexOf('Widget _buildAppVersionDisplay()');
      final end = home.indexOf('String satoshiToBitcoin');
      final body = home.substring(start, end);
      expect(body, contains('installed: _installedApp'));
      // appVersionNrNewest may only feed the separately labelled "newest" value.
      expect(body, contains('newestPublished: payload?.appVersionNrNewest'));
      expect(RegExp(r'installed:\s*[^,]*appVersionNrNewest').hasMatch(body), isFalse);
    });
  });
}
