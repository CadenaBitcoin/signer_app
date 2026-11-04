import 'package:shared_preferences/shared_preferences.dart';

/// Remembers that the first-run security video was offered.
///
/// This is a non-secret UX flag. It lives in shared preferences, which a fresh
/// install does not have, so the offer appears again after reinstall. A full
/// local data wipe also clears it, and the offer is shown once more.
class SecurityVideoOfferStore {
  static const String offeredKey = 'security_video_first_run_offered';

  final SharedPreferences _prefs;

  SecurityVideoOfferStore(this._prefs);

  static Future<SecurityVideoOfferStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SecurityVideoOfferStore(prefs);
  }

  bool get wasOffered => _prefs.getBool(offeredKey) ?? false;

  Future<void> markOffered() => _prefs.setBool(offeredKey, true);
}
