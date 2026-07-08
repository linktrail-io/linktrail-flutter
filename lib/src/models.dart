/// Verbosity of the native SDK's internal logging.
enum LinkTrailLogLevel { debug, info, warning, error, none }

/// Coarse SKAdNetwork conversion value bucket (iOS-only).
enum LinkTrailCoarseConversionValue { low, medium, high }

/// Where a delivered [LinkTrailDeepLink] came from.
enum LinkTrailLinkSource {
  /// The link was tapped before the app was installed (first launch).
  deferred,

  /// The link was tapped while the app was already installed.
  reengagement,
}

/// Retry behavior for the native SDK's network requests.
class LinkTrailRetryPolicy {
  const LinkTrailRetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 8),
  });

  /// No retries.
  static const disabled = LinkTrailRetryPolicy(maxAttempts: 1);

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  Map<String, Object?> toMap() => {
    'maxAttempts': maxAttempts,
    'baseDelayMillis': baseDelay.inMilliseconds,
    'maxDelayMillis': maxDelay.inMilliseconds,
  };
}

/// Configuration passed to [LinkTrail.configure].
class LinkTrailOptions {
  const LinkTrailOptions({
    this.logEnabled = false,
    this.logLevel = LinkTrailLogLevel.info,
    this.requestTimeout = const Duration(seconds: 15),
    this.retryPolicy = const LinkTrailRetryPolicy(),
    this.linkDomains = const [],
    this.autoTrackInstall = true,
  });

  final bool logEnabled;
  final LinkTrailLogLevel logLevel;
  final Duration requestTimeout;
  final LinkTrailRetryPolicy retryPolicy;

  /// Universal Link / App Link hosts that belong to this app (e.g.
  /// `kick.linktrail.io`). Used to decide whether an incoming URL should be
  /// treated as a LinkTrail link.
  final List<String> linkDomains;

  /// Whether [LinkTrail.configure] fires an install/open event automatically.
  final bool autoTrackInstall;

  Map<String, Object?> toMap() => {
    'logEnabled': logEnabled,
    'logLevel': logLevel.name,
    'requestTimeoutMillis': requestTimeout.inMilliseconds,
    'retryPolicy': retryPolicy.toMap(),
    'linkDomains': linkDomains,
    'autoTrackInstall': autoTrackInstall,
  };
}

/// A resolved deep link, as delivered via [LinkTrail.onLink] or returned by
/// [LinkTrail.handleDeepLink].
class LinkTrailDeepLink {
  const LinkTrailDeepLink({
    this.slug,
    this.url,
    this.deepLinkPath,
    this.iosUrl,
    this.androidUrl,
    this.fallbackUrl,
    this.campaign,
    this.channel,
    this.utm,
    this.customData,
  });

  factory LinkTrailDeepLink.fromMap(Map<Object?, Object?> map) {
    return LinkTrailDeepLink(
      slug: map['slug'] as String?,
      url: map['url'] as String?,
      deepLinkPath: map['deepLinkPath'] as String?,
      iosUrl: map['iosUrl'] as String?,
      androidUrl: map['androidUrl'] as String?,
      fallbackUrl: map['fallbackUrl'] as String?,
      campaign: map['campaign'] as String?,
      channel: map['channel'] as String?,
      utm: _stringMap(map['utm']),
      customData: _stringMap(map['customData']),
    );
  }

  final String? slug;
  final String? url;
  final String? deepLinkPath;
  final String? iosUrl;
  final String? androidUrl;
  final String? fallbackUrl;
  final String? campaign;
  final String? channel;
  final Map<String, String>? utm;
  final Map<String, String>? customData;

  /// The path to route on, falling back to `/` when the link carries none.
  String get path => deepLinkPath ?? '/';

  /// Whether this link carries anything to route on beyond the bare host.
  bool get hasRoutableDestination => deepLinkPath != null && deepLinkPath != '/';

  Map<String, Object?> toMap() => {
    'slug': slug,
    'url': url,
    'deepLinkPath': deepLinkPath,
    'iosUrl': iosUrl,
    'androidUrl': androidUrl,
    'fallbackUrl': fallbackUrl,
    'campaign': campaign,
    'channel': channel,
    'utm': utm,
    'customData': customData,
  };

  static Map<String, String>? _stringMap(Object? value) {
    if (value == null) return null;
    return (value as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key as String, value as String),
    );
  }
}

/// A [LinkTrailDeepLink] paired with where it came from — the payload of the
/// [LinkTrail.onLink] stream.
class LinkTrailLinkEvent {
  const LinkTrailLinkEvent(this.link, this.source);

  final LinkTrailDeepLink link;
  final LinkTrailLinkSource source;
}

/// The result of an install/open attribution call.
class LinkTrailAttribution {
  const LinkTrailAttribution({this.id, required this.attributed, this.deepLink});

  factory LinkTrailAttribution.fromMap(Map<Object?, Object?> map) {
    final deepLinkMap = map['deepLink'] as Map<Object?, Object?>?;
    return LinkTrailAttribution(
      id: map['id'] as int?,
      attributed: map['attributed'] as bool,
      deepLink: deepLinkMap == null ? null : LinkTrailDeepLink.fromMap(deepLinkMap),
    );
  }

  final int? id;
  final bool attributed;
  final LinkTrailDeepLink? deepLink;
}

/// The result of a [LinkTrail.trackEvent] call.
class LinkTrailEventResult {
  const LinkTrailEventResult({this.id, required this.attributed});

  factory LinkTrailEventResult.fromMap(Map<Object?, Object?> map) {
    return LinkTrailEventResult(id: map['id'] as int?, attributed: map['attributed'] as bool);
  }

  final int? id;
  final bool attributed;
}
