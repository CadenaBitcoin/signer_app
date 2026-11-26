import 'package:package_info_plus/package_info_plus.dart';

/// The product version and build number of the application that is actually
/// installed on this device, read from the native package metadata:
///
///   Android  versionName / versionCode   (flutter.versionName / flutter.versionCode)
///   iOS      CFBundleShortVersionString / CFBundleVersion
///
/// Both come from the single `version:` line of `pubspec.yaml`
/// (docs/RELEASE_VERSIONING.md), so this is the same value that
/// `tool/verify_artifact.sh` reads back from the built artifact and that the
/// build manifest records. It is never a literal, never read from the backend and
/// never derived from the build environment.
class InstalledAppInfo {
  const InstalledAppInfo({required this.version, required this.buildNumber});

  /// Product version `X.Y.Z`.
  final String version;

  /// Numeric platform build number; empty when the platform does not report one.
  final String buildNumber;

  /// `X.Y.Z (BUILD)`, or `X.Y.Z` when there is no build number.
  String get display => buildNumber.isEmpty ? version : '$version ($buildNumber)';

  /// Reads the installed package metadata. Returns null when it is unavailable
  /// (the platform call failed or reported no version), so that the caller can
  /// show "unavailable" instead of failing or inventing a value.
  ///
  /// [loader] exists for tests; production code uses the platform call.
  static Future<InstalledAppInfo?> load({
    Future<PackageInfo> Function()? loader,
  }) async {
    try {
      final info = await (loader ?? PackageInfo.fromPlatform)();
      final version = info.version.trim();
      if (version.isEmpty) return null;
      return InstalledAppInfo(
        version: version,
        buildNumber: info.buildNumber.trim(),
      );
    } catch (_) {
      return null;
    }
  }
}
