import 'package:flutter/services.dart';

/// Base type for every error the native LinkTrail SDKs can raise, surfaced
/// either as a thrown exception from a `Future`-returning call or as an event
/// on [LinkTrail.onError].
///
/// Mirrors `LinkTrailError` (Android) / `LinkTrailError` (iOS) case-for-case.
sealed class LinkTrailException implements Exception {
  const LinkTrailException(this.message);

  final String message;

  /// Builds the matching subtype from a native [PlatformException], keyed on
  /// `code` — the plugin sets `code` to the same string on both platforms.
  factory LinkTrailException.fromPlatformException(PlatformException e) {
    final message = e.message ?? e.code;
    final details = e.details is Map ? (e.details as Map).cast<String, Object?>() : const {};
    switch (e.code) {
      case 'invalidUrl':
        return LinkTrailInvalidUrlException(details['url'] as String? ?? message);
      case 'transport':
        return LinkTrailTransportException(message);
      case 'server':
        return LinkTrailServerException(
          statusCode: details['statusCode'] as int? ?? 0,
          body: details['body'] as String?,
        );
      case 'decoding':
        return LinkTrailDecodingException(message);
      case 'emptyResponse':
        return const LinkTrailEmptyResponseException();
      case 'notALinkTrailUrl':
        return const LinkTrailNotALinkTrailUrlException();
      case 'missingApiKey':
        return const LinkTrailMissingApiKeyException();
      case 'invalidApiKey':
        return const LinkTrailInvalidApiKeyException();
      default:
        return LinkTrailUnknownException(message);
    }
  }

  @override
  String toString() => '$runtimeType: $message';
}

class LinkTrailInvalidUrlException extends LinkTrailException {
  const LinkTrailInvalidUrlException(String url) : super('Invalid URL: $url');
}

class LinkTrailTransportException extends LinkTrailException {
  const LinkTrailTransportException(super.message);
}

class LinkTrailServerException extends LinkTrailException {
  LinkTrailServerException({required this.statusCode, this.body})
    : super('Server error ($statusCode)${body != null ? ': $body' : ''}');

  final int statusCode;
  final String? body;
}

class LinkTrailDecodingException extends LinkTrailException {
  const LinkTrailDecodingException(super.message);
}

class LinkTrailEmptyResponseException extends LinkTrailException {
  const LinkTrailEmptyResponseException() : super('The server returned an empty response.');
}

class LinkTrailNotALinkTrailUrlException extends LinkTrailException {
  const LinkTrailNotALinkTrailUrlException() : super('The URL is not a LinkTrail link.');
}

class LinkTrailMissingApiKeyException extends LinkTrailException {
  const LinkTrailMissingApiKeyException() : super('An API key is required to configure LinkTrail.');
}

class LinkTrailInvalidApiKeyException extends LinkTrailException {
  const LinkTrailInvalidApiKeyException() : super('The API key was rejected by the server.');
}

/// Fallback for a native error code the Dart layer doesn't recognize yet.
class LinkTrailUnknownException extends LinkTrailException {
  const LinkTrailUnknownException(super.message);
}
