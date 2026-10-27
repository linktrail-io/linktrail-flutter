import 'package:flutter/services.dart';

/// Base type for every error the native LinkTrail SDKs can raise, surfaced
/// either as a thrown exception from a `Future`-returning call or as an event
/// on [LinkTrail.onError].
///
/// Mirrors `LinkTrailError` (Android) / `LinkTrailError` (iOS) case-for-case.
/// [code] is the camelCase native case name (the same on both platforms and in
/// the React Native wrapper) and [message] is the native error's message,
/// passed through unchanged.
sealed class LinkTrailException implements Exception {
  const LinkTrailException(this.code, this.message);

  /// The camelCase error code, e.g. `server` or `notALinkTrailUrl`.
  final String code;

  /// The native SDK's own error message.
  final String message;

  /// Builds the matching subtype from a native [PlatformException], keyed on
  /// `code` — the plugin sets `code` to the same string on both platforms.
  factory LinkTrailException.fromPlatformException(PlatformException e) {
    final message = e.message ?? e.code;
    final details = e.details is Map ? (e.details as Map).cast<String, Object?>() : const <String, Object?>{};
    switch (e.code) {
      case 'invalidUrl':
        return LinkTrailInvalidUrlException(details['url'] as String? ?? '', message);
      case 'transport':
        return LinkTrailTransportException(message);
      case 'server':
        return LinkTrailServerException(
          statusCode: (details['statusCode'] as num?)?.toInt() ?? 0,
          body: details['body'] as String?,
          message: message,
        );
      case 'decoding':
        return LinkTrailDecodingException(message);
      case 'emptyResponse':
        return LinkTrailEmptyResponseException(message);
      case 'notALinkTrailUrl':
        return LinkTrailNotALinkTrailUrlException(message);
      case 'missingApiKey':
        return LinkTrailMissingApiKeyException(message);
      case 'invalidApiKey':
        return LinkTrailInvalidApiKeyException(message);
      case 'notConfigured':
        return LinkTrailNotConfiguredException(message);
      case 'invalidArgument':
        return LinkTrailInvalidArgumentException(message);
      default:
        return LinkTrailUnknownException(message, code: e.code);
    }
  }

  @override
  String toString() => '$runtimeType($code): $message';
}

class LinkTrailInvalidUrlException extends LinkTrailException {
  const LinkTrailInvalidUrlException(this.url, String message) : super('invalidUrl', message);

  /// The URL that could not be built.
  final String url;
}

class LinkTrailTransportException extends LinkTrailException {
  const LinkTrailTransportException(String message) : super('transport', message);
}

class LinkTrailServerException extends LinkTrailException {
  const LinkTrailServerException({required this.statusCode, this.body, required String message})
    : super('server', message);

  /// The HTTP status code the server returned.
  final int statusCode;

  /// The response body, if any.
  final String? body;
}

class LinkTrailDecodingException extends LinkTrailException {
  const LinkTrailDecodingException(String message) : super('decoding', message);
}

class LinkTrailEmptyResponseException extends LinkTrailException {
  const LinkTrailEmptyResponseException(String message) : super('emptyResponse', message);
}

class LinkTrailNotALinkTrailUrlException extends LinkTrailException {
  const LinkTrailNotALinkTrailUrlException(String message) : super('notALinkTrailUrl', message);
}

class LinkTrailMissingApiKeyException extends LinkTrailException {
  const LinkTrailMissingApiKeyException(String message) : super('missingApiKey', message);
}

class LinkTrailInvalidApiKeyException extends LinkTrailException {
  const LinkTrailInvalidApiKeyException(String message) : super('invalidApiKey', message);
}

/// A call was made before [LinkTrail.configure].
class LinkTrailNotConfiguredException extends LinkTrailException {
  const LinkTrailNotConfiguredException(String message) : super('notConfigured', message);
}

/// A required argument was missing or malformed.
class LinkTrailInvalidArgumentException extends LinkTrailException {
  const LinkTrailInvalidArgumentException(String message) : super('invalidArgument', message);
}

/// Fallback for a native error code the Dart layer doesn't recognize yet.
class LinkTrailUnknownException extends LinkTrailException {
  const LinkTrailUnknownException(String message, {String code = 'unknown'}) : super(code, message);
}
