/// Self-custody onboarding video.
///
/// TODO: Replace [kSecurityVideoUrl] with the published Cadena security video.
/// Use a YouTube nocookie embed URL, for example
/// `https://www.youtube-nocookie.com/embed/<videoId>`.
/// Until that URL is real, the app shows the written briefing and does not
/// open a player.
const String kSecurityVideoUrl =
    'https://www.youtube-nocookie.com/embed/VIDEO_ID_PLACEHOLDER';

/// Token that marks [kSecurityVideoUrl] as unpublished. Do not use it in the
/// real video id.
const String kSecurityVideoPlaceholderToken = 'VIDEO_ID_PLACEHOLDER';

/// True when [url] is an https address the app can open.
///
/// Empty values, non-https URLs, and the unpublished placeholder are rejected
/// so a missing video never loads a broken player.
bool isSecurityVideoConfigured(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty || trimmed.contains(kSecurityVideoPlaceholderToken)) {
    return false;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.scheme != 'https') return false;
  if (uri.host.isEmpty) return false;
  return true;
}
