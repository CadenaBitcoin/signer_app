import 'package:signer/config/security_video.dart';
import 'package:url_launcher/url_launcher.dart';

enum SecurityVideoLaunchResult { opened, unavailable, failed }

/// Opens the configured security video outside the app.
///
/// The placeholder URL is never opened. Tests can pass [openUrl] so the
/// platform channel is not called.
class SecurityVideoLauncher {
  const SecurityVideoLauncher({this.openUrl});

  final Future<bool> Function(Uri uri)? openUrl;

  Future<SecurityVideoLaunchResult> open([String url = kSecurityVideoUrl]) async {
    if (!isSecurityVideoConfigured(url)) {
      return SecurityVideoLaunchResult.unavailable;
    }
    try {
      final opener = openUrl ?? _launchExternal;
      final opened = await opener(Uri.parse(url));
      return opened
          ? SecurityVideoLaunchResult.opened
          : SecurityVideoLaunchResult.failed;
    } catch (_) {
      return SecurityVideoLaunchResult.failed;
    }
  }

  static Future<bool> _launchExternal(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
