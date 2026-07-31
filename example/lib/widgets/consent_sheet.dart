import 'package:flutter/material.dart';
import 'package:linktrail_flutter/linktrail_flutter.dart';

import '../consent.dart';

/// First-launch consent prompt. Returns [Consent.granted] / [Consent.denied],
/// or `null` if the user skipped (stays undecided). Mirrors the RN example:
/// Allow / Deny as a selection, a paste button (iOS deferred token), and Skip.
Future<Consent?> showConsentSheet(BuildContext context, {void Function(String token)? onToken}) {
  return showModalBottomSheet<Consent>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ConsentSheet(onToken: onToken),
  );
}

class _ConsentSheet extends StatelessWidget {
  const _ConsentSheet({this.onToken});

  final void Function(String token)? onToken;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + MediaQuery.of(context).viewPadding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.privacy_tip_outlined, size: 40, color: scheme.primary),
          const SizedBox(height: 16),
          Text('Help us attribute your visit',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'KickFlip uses LinkTrail to measure which link brought you here. '
            'Tracking is off until you allow it — deep links still work either way.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.4),
          ),
          const SizedBox(height: 24),
          // iOS-only: the paste control reads the deferred click token with no "Allow Paste" alert.
          // Renders nothing on Android (Play Install Referrer handles deferred attribution there).
          Center(child: LinkTrailPasteButton(onToken: onToken, width: 240)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(context, Consent.granted),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Allow tracking', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, Consent.denied),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Deny'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Skip for now'),
          ),
        ],
      ),
    );
  }
}
