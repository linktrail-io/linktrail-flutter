import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'linktrail_flutter_platform_interface.dart';
import 'src/errors.dart';
import 'src/models.dart';

/// An implementation of [LinktrailFlutterPlatform] that uses method channels.
class MethodChannelLinktrailFlutter extends LinktrailFlutterPlatform {
  /// The method channel used for one-shot calls into the native SDKs.
  @visibleForTesting
  final methodChannel = const MethodChannel('linktrail_flutter');

  static const _onLinkChannel = EventChannel('linktrail_flutter/onLink');
  static const _onAttributionChannel = EventChannel('linktrail_flutter/onAttribution');
  static const _onErrorChannel = EventChannel('linktrail_flutter/onError');

  Stream<LinkTrailLinkEvent>? _onLinkStream;
  Stream<LinkTrailAttribution>? _onAttributionStream;
  Stream<LinkTrailException>? _onErrorStream;

  @override
  Future<void> configure({required String apiKey, required LinkTrailOptions options}) async {
    try {
      await methodChannel.invokeMethod<void>('configure', {
        'apiKey': apiKey,
        'options': options.toMap(),
      });
    } on PlatformException catch (e) {
      throw LinkTrailException.fromPlatformException(e);
    }
  }

  @override
  Stream<LinkTrailLinkEvent> get onLink {
    return _onLinkStream ??= _onLinkChannel.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<Object?, Object?>();
      final link = LinkTrailDeepLink.fromMap((map['link'] as Map).cast<Object?, Object?>());
      final source = LinkTrailLinkSource.values.byName(map['source'] as String);
      return LinkTrailLinkEvent(link, source);
    });
  }

  @override
  Stream<LinkTrailAttribution> get onAttribution {
    return _onAttributionStream ??= _onAttributionChannel.receiveBroadcastStream().map((event) {
      return LinkTrailAttribution.fromMap((event as Map).cast<Object?, Object?>());
    });
  }

  @override
  Stream<LinkTrailException> get onError {
    return _onErrorStream ??= _onErrorChannel.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<Object?, Object?>();
      return LinkTrailException.fromPlatformException(
        PlatformException(
          code: map['code'] as String,
          message: map['message'] as String?,
          details: map['details'],
        ),
      );
    });
  }

  @override
  Future<bool> handleDeepLink(Uri url) async {
    try {
      final handled = await methodChannel.invokeMethod<bool>('handleDeepLink', {
        'url': url.toString(),
      });
      return handled ?? false;
    } on PlatformException catch (e) {
      throw LinkTrailException.fromPlatformException(e);
    }
  }

  @override
  Future<LinkTrailAttribution> trackInstall({required bool force}) async {
    try {
      final map = await methodChannel.invokeMapMethod<Object?, Object?>('trackInstall', {
        'force': force,
      });
      return LinkTrailAttribution.fromMap(map!);
    } on PlatformException catch (e) {
      throw LinkTrailException.fromPlatformException(e);
    }
  }

  @override
  Future<LinkTrailEventResult> trackEvent({required String name, double? value, String? currency}) async {
    try {
      final map = await methodChannel.invokeMapMethod<Object?, Object?>('trackEvent', {
        'name': name,
        'value': value,
        'currency': currency,
      });
      return LinkTrailEventResult.fromMap(map!);
    } on PlatformException catch (e) {
      throw LinkTrailException.fromPlatformException(e);
    }
  }

  @override
  Future<LinkTrailAttribution?> getLastAttribution() async {
    final map = await methodChannel.invokeMapMethod<Object?, Object?>('getLastAttribution');
    return map == null ? null : LinkTrailAttribution.fromMap(map);
  }

  @override
  Future<LinkTrailDeepLink?> getLastDeepLink() async {
    final map = await methodChannel.invokeMapMethod<Object?, Object?>('getLastDeepLink');
    return map == null ? null : LinkTrailDeepLink.fromMap(map);
  }

  @override
  Future<bool> requestTrackingAuthorization() async {
    final granted = await methodChannel.invokeMethod<bool>('requestTrackingAuthorization');
    return granted ?? false;
  }

  @override
  Future<void> registerForSKAdAttribution() {
    return methodChannel.invokeMethod<void>('registerForSKAdAttribution');
  }

  @override
  Future<void> updateConversionValue(int value, {LinkTrailCoarseConversionValue? coarseValue}) {
    return methodChannel.invokeMethod<void>('updateConversionValue', {
      'value': value,
      'coarseValue': coarseValue?.name,
    });
  }

  @override
  Future<void> resetForTesting() {
    return methodChannel.invokeMethod<void>('resetForTesting');
  }
}
