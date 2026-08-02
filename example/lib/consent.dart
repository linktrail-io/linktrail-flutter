import 'package:shared_preferences/shared_preferences.dart';

/// The user's tri-state tracking-consent decision. The SDK has no consent
/// getter, so the app is the source of truth: persist the choice and replay it
/// with `LinkTrail.setConsent` on every launch after `configure`.
enum Consent { granted, denied, undecided }

/// Persists [Consent] locally (SharedPreferences), mirroring the RN example's
/// AsyncStorage-backed store.
class ConsentStore {
  static const _key = 'linktrail_consent';

  Future<Consent> load() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_key)) {
      'granted' => Consent.granted,
      'denied' => Consent.denied,
      _ => Consent.undecided,
    };
  }

  Future<void> save(Consent consent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, consent.name);
  }
}
