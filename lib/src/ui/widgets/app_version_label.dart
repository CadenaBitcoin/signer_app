import 'package:flutter/material.dart';
import 'package:signer/services/installed_app_info.dart';

/// The version line at the top of the Dashboard:
///
///     App: X.Y.Z (BUILD) | API: N            [STAGING]
///     Newest published: X.Y.Z                (only when the backend reports it)
///
/// - `App` is the INSTALLED product version and build number ([installed]), from
///   the native package metadata. It does not depend on the backend, so it stays
///   visible when the version endpoint fails. When the metadata itself cannot be
///   read it says `unavailable`; it never falls back to a backend value.
/// - `API` is the backend's API version, `N/A` while it is not known.
/// - `Newest published` is the backend's newest published app version, under its
///   own label so that it can never be read as the installed version.
/// - The environment marker (`STAGING`) is a separate element and is never part of
///   the version text. Production shows no marker.
class AppVersionLabel extends StatelessWidget {
  const AppVersionLabel({
    super.key,
    required this.installed,
    required this.apiVersion,
    required this.newestPublished,
    required this.environment,
    this.style,
  });

  final InstalledAppInfo? installed;
  final num? apiVersion;
  final String? newestPublished;

  /// `staging` or `production` (BuildConfig.environment).
  final String environment;
  final TextStyle? style;

  /// `App: X.Y.Z (BUILD) | API: N`.
  static String versionLine({
    required InstalledAppInfo? installed,
    required num? apiVersion,
  }) {
    return 'App: ${installed?.display ?? 'unavailable'} | '
        'API: ${apiVersion ?? 'N/A'}';
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? const TextStyle(fontSize: 12);
    final newest = newestPublished?.trim();
    final isStaging = environment == 'staging';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                versionLine(installed: installed, apiVersion: apiVersion),
                key: const Key('app-version-line'),
                style: base,
              ),
            ),
            if (isStaging) ...[
              const SizedBox(width: 8),
              Text(
                'STAGING',
                key: const Key('app-environment-marker'),
                style: base.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
        if (newest != null && newest.isNotEmpty)
          Text(
            'Newest published: $newest',
            key: const Key('app-newest-published'),
            style: base,
          ),
      ],
    );
  }
}
