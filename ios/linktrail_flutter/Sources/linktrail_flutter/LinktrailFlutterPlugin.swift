import Flutter
import LinkTrailSDK
import UIKit

/// Flutter plugin wrapping the native `LinkTrailSDK` iOS SDK.
public class LinktrailFlutterPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  fileprivate var onLinkSink: FlutterEventSink?
  fileprivate var onAttributionSink: FlutterEventSink?
  fileprivate var onErrorSink: FlutterEventSink?

  /// On a cold launch the open-URL / Universal-Link callbacks can fire before Dart has called
  /// configure(), so LinkTrail.shared is still nil and the link would be lost. Buffer it here and
  /// replay it once configure() runs.
  private var pendingLaunchURL: URL?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = LinktrailFlutterPlugin()

    let channel = FlutterMethodChannel(name: "linktrail_flutter", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)

    FlutterEventChannel(name: "linktrail_flutter/onLink", binaryMessenger: registrar.messenger())
      .setStreamHandler(LinkStreamHandler(plugin: instance))
    FlutterEventChannel(name: "linktrail_flutter/onAttribution", binaryMessenger: registrar.messenger())
      .setStreamHandler(AttributionStreamHandler(plugin: instance))
    FlutterEventChannel(name: "linktrail_flutter/onError", binaryMessenger: registrar.messenger())
      .setStreamHandler(ErrorStreamHandler(plugin: instance))

    // Auto-capture Universal Links / custom-scheme opens without any AppDelegate boilerplate.
    // Apps on the classic UIApplicationDelegate lifecycle deliver these to addApplicationDelegate;
    // apps on the iOS 13+ UIScene lifecycle (the default in recent Flutter templates, required on
    // iOS 26) deliver them to addSceneDelegate instead. Register for both so links are captured
    // regardless of which lifecycle the host app uses.
    registrar.addApplicationDelegate(instance)
    registrar.addSceneDelegate(instance)
  }

  /// (Re)registers the native callback hooks on the current `LinkTrail.shared` instance.
  fileprivate func attachHooks() {
    guard let sdk = LinkTrail.shared else { return }
    sdk.onLink { [weak self] link, source in
      self?.onLinkSink?(["link": link.toMap(), "source": source.dartName])
    }
    sdk.onAttribution { [weak self] attribution in
      self?.onAttributionSink?(attribution.toMap())
    }
    sdk.onError { [weak self] error in
      self?.onErrorSink?(toErrorMap(error))
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]

    switch call.method {
    case "configure":
      guard let apiKey = args?["apiKey"] as? String else {
        result(FlutterError(code: "missingApiKey", message: "An API key is required to configure LinkTrail.", details: nil))
        return
      }
      do {
        _ = try LinkTrail.configure(apiKey: apiKey, options: Self.parseOptions(args?["options"] as? [String: Any]))
        attachHooks()
        // Replay a link that launched the app cold, before the SDK was configured.
        if let url = pendingLaunchURL {
          pendingLaunchURL = nil
          LinkTrail.shared?.handleDeepLink(url)
        }
        result(nil)
      } catch {
        result(toFlutterError(error))
      }

    case "handleDeepLink":
      guard let urlString = args?["url"] as? String, let url = URL(string: urlString), let sdk = LinkTrail.shared else {
        result(false)
        return
      }
      result(sdk.handleDeepLink(url))

    case "trackInstall":
      guard let sdk = LinkTrail.shared else {
        result(FlutterError.notConfigured)
        return
      }
      let force = args?["force"] as? Bool ?? false
      Task {
        do {
          result(try await sdk.trackInstall(force: force).toMap())
        } catch {
          result(toFlutterError(error))
        }
      }

    case "trackEvent":
      guard let sdk = LinkTrail.shared else {
        result(FlutterError.notConfigured)
        return
      }
      guard let name = args?["name"] as? String else {
        result(FlutterError(code: "invalidArgument", message: "trackEvent requires a name.", details: nil))
        return
      }
      let value = args?["value"] as? Double
      let currency = args?["currency"] as? String
      Task {
        do {
          result(try await sdk.trackEvent(name: name, value: value, currency: currency).toMap())
        } catch {
          result(toFlutterError(error))
        }
      }

    case "getLastAttribution":
      result(LinkTrail.shared?.lastAttribution?.toMap())

    case "getLastDeepLink":
      result(LinkTrail.shared?.lastDeepLink?.toMap())

    case "requestTrackingAuthorization":
      guard let sdk = LinkTrail.shared else {
        result(false)
        return
      }
      Task { result(await sdk.requestTrackingAuthorization()) }

    case "registerForSKAdAttribution":
      LinkTrail.shared?.registerForSKAdAttribution()
      result(nil)

    case "updateConversionValue":
      let value = args?["value"] as? Int ?? 0
      let coarse = (args?["coarseValue"] as? String).flatMap(LinkTrailCoarseConversionValue.init(dartName:))
      LinkTrail.shared?.updateConversionValue(value, coarseValue: coarse)
      result(nil)

    case "resetForTesting":
      LinkTrail.resetForTesting()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func parseOptions(_ map: [String: Any]?) -> LinkTrailOptions {
    guard let map else { return LinkTrailOptions() }
    let retryMap = map["retryPolicy"] as? [String: Any]
    let logLevel = (map["logLevel"] as? String).flatMap(LinkTrailLogLevel.init(dartName:)) ?? .info
    return LinkTrailOptions(
      logEnabled: map["logEnabled"] as? Bool ?? false,
      logLevel: logLevel,
      requestTimeout: ((map["requestTimeoutMillis"] as? NSNumber)?.doubleValue ?? 15_000) / 1000,
      retryPolicy: LinkTrailRetryPolicy(
        maxAttempts: (retryMap?["maxAttempts"] as? NSNumber)?.intValue ?? 3,
        baseDelay: ((retryMap?["baseDelayMillis"] as? NSNumber)?.doubleValue ?? 500) / 1000,
        maxDelay: ((retryMap?["maxDelayMillis"] as? NSNumber)?.doubleValue ?? 8_000) / 1000
      ),
      linkDomains: map["linkDomains"] as? [String] ?? [],
      autoTrackInstall: map["autoTrackInstall"] as? Bool ?? true
    )
  }

  // -- Auto-capture (classic UIApplicationDelegate lifecycle). --

  public func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    handleOrBufferLaunchURL(url)
  }

  public func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL else {
      return false
    }
    return handleOrBufferLaunchURL(url)
  }

  // -- Auto-capture (iOS 13+ UIScene lifecycle — the path used on iOS 26). --

  /// Cold start: the app was launched from a killed state by a link, delivered in the scene's
  /// connection options. Fires before Dart configure(), so the URL is buffered and replayed.
  public func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    var handled = false
    for context in connectionOptions?.urlContexts ?? [] {
      handled = handleOrBufferLaunchURL(context.url) || handled
    }
    for activity in connectionOptions?.userActivities ?? [] where activity.activityType == NSUserActivityTypeBrowsingWeb {
      if let url = activity.webpageURL { handled = handleOrBufferLaunchURL(url) || handled }
    }
    return handled
  }

  /// Warm: a custom-scheme link opened while the app was already running.
  public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    var handled = false
    for context in URLContexts {
      handled = handleOrBufferLaunchURL(context.url) || handled
    }
    return handled
  }

  /// Warm: a Universal Link opened while the app was already running.
  public func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL else {
      return false
    }
    return handleOrBufferLaunchURL(url)
  }

  /// Handle the URL now if the SDK is configured, otherwise buffer it for replay after configure().
  @discardableResult
  private func handleOrBufferLaunchURL(_ url: URL) -> Bool {
    if let sdk = LinkTrail.shared {
      return sdk.handleDeepLink(url)
    }
    pendingLaunchURL = url
    return true
  }
}

private final class LinkStreamHandler: NSObject, FlutterStreamHandler {
  private weak var plugin: LinktrailFlutterPlugin?
  init(plugin: LinktrailFlutterPlugin) { self.plugin = plugin }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    plugin?.onLinkSink = events
    plugin?.attachHooks()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    plugin?.onLinkSink = nil
    return nil
  }
}

private final class AttributionStreamHandler: NSObject, FlutterStreamHandler {
  private weak var plugin: LinktrailFlutterPlugin?
  init(plugin: LinktrailFlutterPlugin) { self.plugin = plugin }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    plugin?.onAttributionSink = events
    plugin?.attachHooks()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    plugin?.onAttributionSink = nil
    return nil
  }
}

private final class ErrorStreamHandler: NSObject, FlutterStreamHandler {
  private weak var plugin: LinktrailFlutterPlugin?
  init(plugin: LinktrailFlutterPlugin) { self.plugin = plugin }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    plugin?.onErrorSink = events
    plugin?.attachHooks()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    plugin?.onErrorSink = nil
    return nil
  }
}

extension FlutterError {
  static var notConfigured: FlutterError {
    FlutterError(code: "notConfigured", message: "LinkTrail.configure() must be called before this method.", details: nil)
  }
}

extension LinkTrailDeepLink {
  fileprivate func toMap() -> [String: Any?] {
    [
      "slug": slug,
      "url": url,
      "deepLinkPath": deepLinkPath,
      "iosUrl": iosURL,
      "androidUrl": androidURL,
      "fallbackUrl": fallbackURL,
      "campaign": campaign,
      "channel": channel,
      "utm": utm,
      "customData": customData,
    ]
  }
}

extension LinkTrailAttribution {
  fileprivate func toMap() -> [String: Any?] {
    ["id": id, "attributed": attributed, "deepLink": deepLink?.toMap()]
  }
}

extension LinkTrailEventResult {
  fileprivate func toMap() -> [String: Any?] {
    ["id": id, "attributed": attributed]
  }
}

extension LinkTrailLinkSource {
  fileprivate var dartName: String {
    switch self {
    case .deferred: return "deferred"
    case .reengagement: return "reengagement"
    }
  }
}

extension LinkTrailLogLevel {
  fileprivate init?(dartName: String) {
    switch dartName {
    case "debug": self = .debug
    case "info": self = .info
    case "warning": self = .warning
    case "error": self = .error
    case "none": self = .none
    default: return nil
    }
  }
}

extension LinkTrailCoarseConversionValue {
  fileprivate init?(dartName: String) {
    switch dartName {
    case "low": self = .low
    case "medium": self = .medium
    case "high": self = .high
    default: return nil
    }
  }
}

/// Maps a caught native error to a `FlutterError` whose `code` matches the Dart `LinkTrailException` codes.
///
/// A free function rather than an `Error` extension: pattern-matching concrete `LinkTrailError`
/// cases against `Self` inside a protocol extension doesn't type-check (`Self` isn't statically
/// known to be `LinkTrailError`), but matching against a plain `Error`-typed parameter does.
private func toFlutterError(_ error: Error) -> FlutterError {
  let (code, details): (String, [String: Any?]) =
    switch error {
    case LinkTrailError.invalidURL(let url): ("invalidUrl", ["url": url])
    case LinkTrailError.transport(let message): ("transport", ["message": message])
    case LinkTrailError.server(let statusCode, let body): ("server", ["statusCode": statusCode, "body": body])
    case LinkTrailError.decoding(let message): ("decoding", ["message": message])
    case LinkTrailError.emptyResponse: ("emptyResponse", [:])
    case LinkTrailError.notALinkTrailURL: ("notALinkTrailUrl", [:])
    case LinkTrailError.missingAPIKey: ("missingApiKey", [:])
    case LinkTrailError.invalidAPIKey: ("invalidApiKey", [:])
    default: ("unknown", [:])
    }
  return FlutterError(code: code, message: error.localizedDescription, details: details)
}

private func toErrorMap(_ error: Error) -> [String: Any?] {
  let flutterError = toFlutterError(error)
  return ["code": flutterError.code, "message": flutterError.message, "details": flutterError.details]
}
