import 'package:flutter/material.dart';
import 'package:linktrail_flutter/linktrail_flutter.dart';

/// Shows the E2E panel. Off by default; the Maestro smoke suite (`e2e/`) builds the example with
/// `--dart-define=E2E=true`.
const bool kE2EPanel = bool.fromEnvironment('E2E');

/// What the Maestro smoke flows assert on: every `onLink` delivery (so "fired exactly once" is
/// checkable), the consent decision and the last `trackEvent` result.
class E2EState extends ChangeNotifier {
  int linkCount = 0;
  LinkTrailLinkEvent? lastLink;
  String consent = 'undecided';
  String trackEventResult = 'none';

  void recordLink(LinkTrailLinkEvent event) {
    linkCount++;
    lastLink = event;
    notifyListeners();
  }

  void recordConsent(String value) {
    consent = value;
    notifyListeners();
  }

  void recordTrackEvent(String value) {
    trackEventResult = value;
    notifyListeners();
  }

  /// `customData` as sorted `key=value` pairs, so a flow can assert one pair by regex.
  static String formatCustomData(Map<String, String>? data) {
    if (data == null || data.isEmpty) return 'none';
    final keys = data.keys.toList()..sort();
    return keys.map((k) => '$k=${data[k]}').join(', ');
  }
}

/// The panel itself. Each line has a semantics identifier (Android resource-id, iOS
/// accessibilityIdentifier) and readable text, so Maestro can match by `id:` or by text.
class E2EPanel extends StatefulWidget {
  const E2EPanel({super.key, required this.state});

  final E2EState state;

  @override
  State<E2EPanel> createState() => _E2EPanelState();
}

class _E2EPanelState extends State<E2EPanel> {
  final _url = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _trackEvent() async {
    try {
      final result = await LinkTrail.trackEvent(name: 'e2e_purchase', value: 9.99, currency: 'USD');
      widget.state.recordTrackEvent('ok id=${result.id} value=9.99 USD');
    } on LinkTrailException catch (e) {
      widget.state.recordTrackEvent('error ${e.code}');
    }
  }

  Future<void> _handleLink() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null) return;
    await LinkTrail.handleDeepLink(uri);
  }

  Widget _line(String id, String text) => Semantics(
        identifier: id,
        container: true,
        child: Text(text, key: ValueKey(id), style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final s = widget.state;
        final link = s.lastLink;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _line('e2e-consent', 'consent: ${s.consent}'),
              _line('e2e-link-count', 'onLink count: ${s.linkCount}'),
              _line('e2e-link-source', 'source: ${link?.source.name ?? 'none'}'),
              _line('e2e-link-path', 'path: ${link?.link.path ?? 'none'}'),
              _line('e2e-link-custom-data', 'customData: ${E2EState.formatCustomData(link?.link.customData)}'),
              _line('e2e-track-event', 'trackEvent: ${s.trackEventResult}'),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      identifier: 'e2e-link-input',
                      child: TextField(
                        key: const ValueKey('e2e-link-input'),
                        controller: _url,
                        decoration: const InputDecoration(isDense: true, hintText: 'link URL'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  Semantics(
                    identifier: 'e2e-handle-link',
                    child: TextButton(onPressed: _handleLink, child: const Text('Open link')),
                  ),
                  Semantics(
                    identifier: 'e2e-track-event-button',
                    child: TextButton(onPressed: _trackEvent, child: const Text('Track event')),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
