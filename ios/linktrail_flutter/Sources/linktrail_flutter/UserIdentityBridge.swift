import Foundation

/// User identity (setUserId / logout) persistence + best-effort forwarding to the wrapped native
/// SDK. The pinned `LinkTrailSDK` release predates user identity, so the SDK call goes through an
/// Objective-C selector guard and is skipped when the SDK does not expose it. Dart validates the
/// id and owns consent gating; this type only persists and forwards.
enum UserIdentityBridge {
  private static let key = "io.linktrail.flutter.user_id"

  static func storedUserId() -> String? {
    UserDefaults.standard.string(forKey: key)
  }

  static func set(userId: String?, consented: Bool, sdk: AnyObject?) {
    if let userId {
      UserDefaults.standard.set(userId, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
    guard let sdk else { return }
    if let userId {
      guard consented else { return }
      let selector = NSSelectorFromString("setUserId:")
      if sdk.responds(to: selector) { _ = sdk.perform(selector, with: userId) }
    } else {
      let selector = NSSelectorFromString("logout")
      if sdk.responds(to: selector) { _ = sdk.perform(selector) }
    }
  }
}
