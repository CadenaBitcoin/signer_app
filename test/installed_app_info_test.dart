import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:signer/services/installed_app_info.dart';

PackageInfo _pkg(String version, String build) => PackageInfo(
      appName: 'Cadena',
      packageName: 'com.example.test',
      version: version,
      buildNumber: build,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InstalledAppInfo.load', () {
    test('reads the product version and the build number separately', () async {
      final info = await InstalledAppInfo.load(
        loader: () async => _pkg('1.0.4', '1000035'),
      );
      expect(info, isNotNull);
      expect(info!.version, '1.0.4');
      expect(info.buildNumber, '1000035');
      expect(info.display, '1.0.4 (1000035)');
    });

    test('reads the native package metadata when no loader is given', () async {
      PackageInfo.setMockInitialValues(
        appName: 'Cadena',
        packageName: 'com.example.test',
        version: '2.3.4',
        buildNumber: '2000001',
        buildSignature: '',
      );
      final info = await InstalledAppInfo.load();
      expect(info?.version, '2.3.4');
      expect(info?.buildNumber, '2000001');
    });

    test('trims whitespace', () async {
      final info = await InstalledAppInfo.load(
        loader: () async => _pkg(' 1.0.4 ', ' 1000035 '),
      );
      expect(info?.display, '1.0.4 (1000035)');
    });

    test('shows the version alone when the platform reports no build number',
        () async {
      final info = await InstalledAppInfo.load(
        loader: () async => _pkg('1.0.4', ''),
      );
      expect(info?.display, '1.0.4');
    });

    test('is null when the platform call fails', () async {
      final info = await InstalledAppInfo.load(
        loader: () async => throw Exception('platform channel unavailable'),
      );
      expect(info, isNull);
    });

    test('is null when the platform reports no version', () async {
      final info = await InstalledAppInfo.load(
        loader: () async => _pkg('', '1000035'),
      );
      expect(info, isNull);
    });
  });
}
