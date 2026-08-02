import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:linktrail_flutter/linktrail_flutter.dart';

import '../consent.dart';

/// First-launch consent prompt. Returns [Consent.granted] / [Consent.denied],
/// or `null` if the user skipped (stays undecided).
///
/// Layout: an **Allow / Deny** selectable row (purely a selection — takes no
/// action), then a full-width **paste** button (tapping it means *allow* +
/// reads the iOS deferred token), then **Skip** last.
Future<Consent?> showConsentSheet(BuildContext context, {void Function(String token)? onToken}) {
  return showModalBottomSheet<Consent>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ConsentSheet(onToken: onToken),
  );
}

class _ConsentSheet extends StatefulWidget {
  const _ConsentSheet({this.onToken});

  final void Function(String token)? onToken;

  @override
  State<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<_ConsentSheet> {
  // Selection only — highlights a choice but performs no SDK action (per the demo's design).
  Consent _selected = Consent.granted;

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
          // Allow / Deny — a selectable segmented row. Selection only; no action taken here.
          Row(
            children: [
              Expanded(child: _SelectableChip(
                label: 'Allow tracking',
                selected: _selected == Consent.granted,
                onTap: () => setState(() => _selected = Consent.granted),
              )),
              const SizedBox(width: 12),
              Expanded(child: _SelectableChip(
                label: 'Deny',
                selected: _selected == Consent.denied,
                onTap: () => setState(() => _selected = Consent.denied),
              )),
            ],
          ),
          const SizedBox(height: 16),
          // Full-width primary action below the row.
          //  • iOS: the native paste button (tapping it = allow + read the deferred token).
          //  • Android: a "Continue" button that commits the selected Allow/Deny choice (there is no
          //    paste control on Android — the Play Install Referrer handles deferred attribution).
          if (!kIsWeb && Platform.isIOS)
            LinkTrailPasteButton(
              color: scheme.primary,
              onToken: (token) {
                widget.onToken?.call(token);
                if (mounted) Navigator.pop(context, null); // onToken commits; nothing more to do
              },
            )
          else
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _selected),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          const SizedBox(height: 4),
          // Skip — last button, simply dismisses (stays undecided).
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }
}

class _SelectableChip extends StatelessWidget {
  const _SelectableChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? scheme.primary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
