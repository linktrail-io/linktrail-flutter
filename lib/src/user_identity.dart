import 'package:flutter/foundation.dart';

import '../linktrail_flutter_platform_interface.dart';

final _userIdPattern = RegExp(r'^[A-Za-z0-9_.:-]{1,128}$');

/// Whether [userId] is a valid LinkTrail user id: 1-128 characters from
/// `A-Za-z0-9 _ - . :`.
bool isValidLinkTrailUserId(String userId) => _userIdPattern.hasMatch(userId);

/// Dart-side owner of the user identity. Validates ids, mirrors the consent
/// state the app reports, and delegates persistence / native forwarding to the
/// platform layer. Internal: use `LinkTrail.setUserId` / `LinkTrail.logout`.
@internal
class UserIdentity {
  /// `null` until the app calls `setConsent`.
  static bool? _consent;

  static Future<void> setUserId(String userId) async {
    if (!isValidLinkTrailUserId(userId)) {
      throw ArgumentError.value(
        userId,
        'userId',
        'Must be 1-128 characters of A-Z a-z 0-9 _ - . : (use an opaque internal id or a hash, never PII).',
      );
    }
    await LinktrailFlutterPlatform.instance.setUserId(userId, consented: _consent == true);
  }

  static Future<void> logout() {
    return LinktrailFlutterPlatform.instance.setUserId(null, consented: _consent == true);
  }

  static Future<String?> get userId => LinktrailFlutterPlatform.instance.getUserId();

  /// Called by `LinkTrail.setConsent`. On a grant, re-applies a stored id so
  /// the native layer can identify the now-consented device; on a denial the
  /// id stays stored locally but is never transmitted.
  static Future<void> onConsentChanged(bool granted) async {
    _consent = granted;
    if (!granted) return;
    await _reapply();
  }

  /// Called after `configure`: re-applies a persisted id to the native SDK.
  static Future<void> restore() => _reapply();

  static Future<void> _reapply() async {
    try {
      final id = await LinktrailFlutterPlatform.instance.getUserId();
      if (id != null && isValidLinkTrailUserId(id)) {
        await LinktrailFlutterPlatform.instance.setUserId(id, consented: _consent == true);
      }
    } catch (_) {
      // Identity is best-effort and must never fail configure/setConsent.
    }
  }

  @visibleForTesting
  static void resetConsentForTesting() => _consent = null;
}
