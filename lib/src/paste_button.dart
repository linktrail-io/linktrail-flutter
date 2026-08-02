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
/// The control fills its parent's width; give it a bounded width (e.g. inside a
/// `Column` with `crossAxisAlignment: stretch`) and it lays out full width.
/// [color] themes the button fill (defaults to the ambient primary color).
/// Apple restricts the rest of the appearance — no custom label text or font.
class LinkTrailPasteButton extends StatelessWidget {
  const LinkTrailPasteButton({super.key, this.onToken, this.color, this.height = 48});

  /// Fires with the click token after the SDK reads it from the pasted content.
  final void Function(String token)? onToken;

  /// Fill color for the button. Defaults to the theme's primary color.
  final Color? color;

  final double height;

  static const _viewType = 'linktrail_flutter/paste_button';

  @override
  Widget build(BuildContext context) {
    final isIOS = !kIsWeb && Platform.isIOS;
    if (!isIOS) return SizedBox(height: height);

    final fill = color ?? const Color(0xFF6C4DF6);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: UiKitView(
        viewType: _viewType,
        creationParams: <String, Object?>{'color': _argb(fill)},
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

  static int _argb(Color c) {
    int ch(double v) => (v * 255).round() & 0xFF;
    return (ch(c.a) << 24) | (ch(c.r) << 16) | (ch(c.g) << 8) | ch(c.b);
  }
}
