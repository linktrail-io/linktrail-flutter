import 'package:flutter/material.dart';

import '../scenarios.dart';

/// Shows the four deferred-deep-link scenarios and returns the chosen one,
/// mirroring the native KickFlip example apps' debug simulator panel.
Future<DeepLinkScenario?> showSimulatorSheet(BuildContext context) {
  return showModalBottomSheet<DeepLinkScenario>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Simulate a link', style: TextStyle(fontSize: 18))),
          for (final scenario in deepLinkScenarios)
            ListTile(
              title: Text(scenario.title),
              subtitle: Text(scenario.subtitle),
              onTap: () => Navigator.of(context).pop(scenario),
            ),
        ],
      ),
    ),
  );
}
