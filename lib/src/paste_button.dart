import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Apple's `UIPasteControl` for deferred-attribution — reads the click token
/// the tapped link left on the clipboard **without** the system "Allow Paste"
/// alert, and hands it to the LinkTrail SDK to complete the install.
///
/// iOS 16+ only. Use with `LinkTrailOptions(clickTokenSource: pasteButton,
/// autoTrackInstall: false)` so the install waits for the tap. On Android (and
/// non-iOS platforms) this renders nothing — Android uses the Play Install
/// Referrer, so no paste button is needed.
///
/// Apple restricts how the control looks; the label text, font and border can't
/// be customized. Size it with [width] / [height].
class LinkTrailPasteButton extends StatelessWidget {
  const LinkTrailPasteButton({super.key, this.onToken, this.width = 220, this.height = 44});

  /// Fires with the click token after the SDK reads it from the pasted content.
  /// The SDK completes the install on tap; this is a notification hook.
  final void Function(String token)? onToken;

  final double width;
  final double height;

  static const _viewType = 'linktrail_flutter/paste_button';

  @override
  Widget build(BuildContext context) {
    final isIOS = !kIsWeb && Platform.isIOS;
    if (!isIOS) return SizedBox(width: width, height: height);

    return SizedBox(
      width: width,
      height: height,
      child: UiKitView(
        viewType: _viewType,
        creationParams: const <String, Object?>{},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onCreated,
      ),
    );
  }

  void _onCreated(int id) {
    final channel = MethodChannel('$_viewType/$id');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onToken') {
        onToken?.call(call.arguments as String);
      }
      return null;
    });
  }
}
