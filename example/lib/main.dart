import 'dart:async';

import 'package:flutter/material.dart';
import 'package:linktrail_flutter/linktrail_flutter.dart';

import 'consent.dart';
import 'store.dart';
import 'screens/home_screen.dart';
import 'screens/product_screen.dart';
import 'widgets/consent_sheet.dart';
import 'widgets/simulator_sheet.dart';

/// Your workspace SDK key (`lt_live_…`) from the LinkTrail dashboard, supplied at
/// build time so it never lands in source control:
///
///   flutter run --dart-define=LINKTRAIL_API_KEY=lt_live_your_key
///
/// Without it the backend rejects the request, surfaced below via [LinkTrail.onError]
/// as `LinkTrailInvalidApiKeyException`.
const _apiKey = String.fromEnvironment('LINKTRAIL_API_KEY', defaultValue: 'lt_live_ffd42e47b055b3d0cfe093ba8acc62aac2b88c08907d6a55');

void main() {
  runApp(const KickFlipDemoApp());
}

class KickFlipDemoApp extends StatefulWidget {
  const KickFlipDemoApp({super.key});

  @override
  State<KickFlipDemoApp> createState() => _KickFlipDemoAppState();
}

class _KickFlipDemoAppState extends State<KickFlipDemoApp> {
  final Store _store = Store();
  final ConsentStore _consentStore = ConsentStore();
  String? _status;

  final _navigatorKey = GlobalKey<NavigatorState>();

  StreamSubscription<LinkTrailLinkEvent>? _onLinkSub;
  StreamSubscription<LinkTrailException>? _onErrorSub;
  StreamSubscription<LinkTrailAttribution>? _onAttributionSub;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _configureSdk();
  }

  Future<void> _configureSdk() async {
    // §5 lesson: wire onLink BEFORE any async work. A cold-start deep link is delivered right
    // after configure — if we awaited consent-loading first, the delivery would land with no
    // listener and be lost.
    _onLinkSub = LinkTrail.onLink.listen((event) {
      _store.route(event.link, event.source);
    });
    _onAttributionSub = LinkTrail.onAttribution.listen((attribution) {
      setState(() => _status = 'Attribution · attributed=${attribution.attributed}');
    });
    _onErrorSub = LinkTrail.onError.listen((error) {
      setState(() => _status = 'Error · $error');
    });

    try {
      await LinkTrail.configure(
        apiKey: _apiKey,
        // Deny-by-default consent gating (requireConsent), plus the iOS paste-button deferred-token
        // flow (clickTokenSource + autoTrackInstall:false so the install waits for the tap).
        options: const LinkTrailOptions(
          logEnabled: true,
          linkDomains: ['kick.linktrail.io'],
          requireConsent: true,
          autoTrackInstall: false,
          clickTokenSource: LinkTrailClickTokenSource.pasteButton,
        ),
      );
    } on LinkTrailException catch (e) {
      setState(() => _status = 'Configure failed · $e');
      return;
    }

    await _applyConsent();
  }

  /// Replays the persisted consent decision (the SDK has no getter), then prompts on first launch.
  Future<void> _applyConsent() async {
    final consent = await _consentStore.load();
    if (consent != Consent.undecided) {
      await LinkTrail.setConsent(consent == Consent.granted);
      if (consent == Consent.granted) await LinkTrail.trackInstall();
      return;
    }
    // Undecided → prompt after the first frame so a Navigator/context is available.
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptForConsent());
  }

  Future<void> _promptForConsent() async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    // iOS paste (onToken) = allow + deferred token: grant consent first (so the gated install can
    // proceed), persist, then install with the token; the sheet then returns null (already handled).
    // Android returns the selected Allow/Deny via "Continue". Skip returns null (stays undecided).
    final decision = await showConsentSheet(
      context,
      onToken: (token) async {
        await LinkTrail.setConsent(true);
        await _consentStore.save(Consent.granted);
        try {
          await LinkTrail.trackInstallWithClickToken(token);
          setState(() => _status = 'Consent granted · install tracked (token)');
        } on LinkTrailException catch (e) {
          setState(() => _status = 'Token install failed · $e');
        }
      },
    );
    if (decision == null) return; // skipped, or iOS paste already handled in onToken
    await _consentStore.save(decision);
    await LinkTrail.setConsent(decision == Consent.granted);
    if (decision == Consent.granted) await LinkTrail.trackInstall();
    setState(() => _status = 'Consent · ${decision.name}');
  }

  void _onStoreChanged() => setState(() {});

  Future<void> _openSimulator(BuildContext context) async {
    final scenario = await showSimulatorSheet(context);
    if (scenario != null) _store.simulate(scenario.link);
  }

  @override
  void dispose() {
    _onLinkSub?.cancel();
    _onErrorSub?.cancel();
    _onAttributionSub?.cancel();
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = _store.screen;
    return MaterialApp(
      title: 'KickFlip',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C4DF6)),
        scaffoldBackgroundColor: const Color(0xFFF6F5FB),
        useMaterial3: true,
      ),
      // Screens are switched by state (_store.screen) rather than Navigator routes, so the OS
      // back button/gesture has nothing to pop. PopScope bridges it into the store: on a product
      // page, intercept the back and go Home; on Home, allow the pop so back exits the app.
      home: PopScope(
        canPop: screen is HomeScreen,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _store.screen is ProductDetailScreen) _store.goHome();
        },
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            scrolledUnderElevation: 0,
            leading: screen is ProductDetailScreen
                ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _store.goHome)
                : null,
            title: Text(
              screen is ProductDetailScreen ? screen.product.name : 'KickFlip',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: [
              // Builder hands us a BuildContext under MaterialApp (this State's own `context` sits
              // above it), which showModalBottomSheet requires to find Localizations.
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.link_rounded),
                  tooltip: 'Simulate a link',
                  onPressed: () => _openSimulator(context),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            top: false,
            child: switch (screen) {
              HomeScreen() => HomeScreenView(store: _store, status: _status),
              ProductDetailScreen(:final product, :final voucher) => ProductScreenView(
                product: product,
                voucher: voucher,
              ),
            },
          ),
        ),
      ),
    );
  }
}
