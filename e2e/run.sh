#!/usr/bin/env bash
# Maestro smoke e2e for the LinkTrail Flutter plugin, driven against the example app built from
# this checkout (the plugin is a path dependency, so the Dart and native bridge code under test is
# the local source; the native SDKs come from the versions the plugin pins).
#
# Usage:
#   bash e2e/run.sh android [flow …]    # a booted emulator/device (adb)
#   bash e2e/run.sh ios [flow …]        # a booted simulator (DEVICE=<udid> to pick one)
# Flow names are the files in e2e/flows without .yaml. Default: all six.
#
# Flows:
#   consent_allow, consent_deny          local: no secrets, no click
#   deferred_allow, deferred_deny        real: a real click on LINK_URL, then the backend check
#   reengagement, track_event            real: need the SDK key
# Without LINKTRAIL_KEY the real flows are skipped with a notice and only the local ones run.
#
# Env:
#   LINKTRAIL_KEY       SDK key for the workspace that owns LINK_URL. Reaches the build through a
#                       private temp file (--dart-define-from-file), never argv. Never printed.
#   E2E_TOKEN           X-E2E-Token for GET /v1/e2e/clicks/<token> (e2e/verify.sh). Never printed.
#   E2E_VERIFY_REQUIRED 1 = a missing E2E_TOKEN fails the deferred flows instead of skipping the check.
#   LINK_URL            campaign link (default https://kick.linktrail.io/discounted-product)
#   BACKEND_URL         default https://backend.linktrail.io
#   RETRIES             attempts per flow (default 2)
#   ANDROID_FAKE_REFERRER  auto (default) | 1 | 0. The debug referrer override
#                       (debug.linktrail.referrer) ships after io.linktrail:sdk 0.0.5; on auto the
#                       Android deferred flows are skipped while the plugin pins 0.0.5 or older.
set -euo pipefail
export PATH="$HOME/.maestro/bin:$PATH"

PLATFORM="${1:-}"; shift || true
case "$PLATFORM" in android|ios) ;; *) echo "usage: $0 android|ios [flow …]" >&2; exit 2 ;; esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
E2E="$ROOT/e2e"
FLOWS_DIR="$E2E/flows"
EXAMPLE="$ROOT/example"
LINK_URL="${LINK_URL:-https://kick.linktrail.io/discounted-product}"
BACKEND_URL="${BACKEND_URL:-https://backend.linktrail.io}"
VERIFY_BASE="$BACKEND_URL"
RETRIES="${RETRIES:-2}"
CLICK_WAIT="${CLICK_WAIT:-60}"
ANDROID_UA="Mozilla/5.0 (Linux; Android 15; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
ALL_FLOWS="consent_allow consent_deny deferred_allow deferred_deny reengagement track_event"

if [ "$PLATFORM" = android ]; then APP_ID="io.linktrail.example"; else APP_ID="io.linktrail.kickflipdemo"; fi

# shellcheck source=e2e/verify.sh
source "$E2E/verify.sh"

note() { if [ "${GITHUB_ACTIONS:-}" = true ]; then echo "::notice title=e2e::$*"; else echo "NOTE: $*"; fi; }
warn() { if [ "${GITHUB_ACTIONS:-}" = true ]; then echo "::warning title=e2e::$*"; else echo "WARN: $*"; fi; }

command -v maestro >/dev/null 2>&1 || { echo "ERROR: maestro not found (curl -Ls https://get.maestro.mobile.dev | bash)"; exit 1; }
command -v flutter >/dev/null 2>&1 || { echo "ERROR: flutter not found"; exit 1; }

HAVE_KEY=0; [ -n "${LINKTRAIL_KEY:-}" ] && HAVE_KEY=1

FLOWS="${*:-$ALL_FLOWS}"
for f in $FLOWS; do [ -f "$FLOWS_DIR/$f.yaml" ] || { echo "ERROR: no flow e2e/flows/$f.yaml"; exit 2; }; done

is_real() { case "$1" in consent_*) return 1 ;; *) return 0 ;; esac; }

# Which native Android SDK the plugin pins, and whether it has the debug referrer override.
android_has_fake_referrer() {
  case "${ANDROID_FAKE_REFERRER:-auto}" in 1) return 0 ;; 0) return 1 ;; esac
  local v
  v="$(grep -oE 'io\.linktrail:sdk:[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/android/build.gradle.kts" | head -1 | cut -d: -f3)"
  python3 -I -c 'import sys; v = tuple(int(x) for x in sys.argv[1].split(".")); sys.exit(0 if v > (0, 0, 5) else 1)' "${v:-0.0.0}"
}

# ── Build ────────────────────────────────────────────────────────────────────────────────────
DEFINES="$(mktemp)"; chmod 600 "$DEFINES"
trap 'rm -f "$DEFINES"' EXIT
python3 -I -c '
import json, os, sys
d = {"E2E": "true"}
if os.environ.get("LINKTRAIL_KEY"): d["LINKTRAIL_API_KEY"] = os.environ["LINKTRAIL_KEY"]
json.dump(d, open(sys.argv[1], "w"))
' "$DEFINES"

echo "==> Building the example ($PLATFORM, E2E panel on, SDK key: $([ $HAVE_KEY = 1 ] && echo set || echo not set))"
( cd "$EXAMPLE" && flutter pub get >/dev/null )
if [ "$PLATFORM" = android ]; then
  ( cd "$EXAMPLE" && flutter build apk --debug --dart-define-from-file="$DEFINES" >/dev/null )
  APP="$EXAMPLE/build/app/outputs/flutter-apk/app-debug.apk"
else
  # `flutter build ios --simulator` trips over its own lipo arch check with Xcode 27 ("does not
  # contain architectures arm64 x86_64"), so Flutter only writes the config (incl. the dart-defines)
  # and xcodebuild builds the host arch. The build log can hold the defines, so it is never printed
  # whole and is deleted afterwards.
  export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
  ( cd "$EXAMPLE" && flutter build ios --config-only --simulator --debug --dart-define-from-file="$DEFINES" >/dev/null )
  XLOG="$(mktemp)"
  if ! xcodebuild -workspace "$EXAMPLE/ios/Runner.xcworkspace" -scheme Runner -configuration Debug \
      -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$EXAMPLE/build/e2e-derived" ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=NO \
      CODE_SIGNING_ALLOWED=NO build >"$XLOG" 2>&1; then
    echo "ERROR: iOS build failed:"; grep -E '(error|warning: .*fatal):' "$XLOG" | grep -v DART_DEFINES | head -20
    rm -f "$XLOG"; exit 1
  fi
  rm -f "$XLOG"
  # Rewrite the generated config without the key, so it does not stay on disk.
  printf '{"E2E": "true"}' > "$DEFINES"
  ( cd "$EXAMPLE" && flutter build ios --config-only --simulator --debug --dart-define-from-file="$DEFINES" >/dev/null )
  APP="$EXAMPLE/build/e2e-derived/Build/Products/Debug-iphonesimulator/Runner.app"
fi
rm -f "$DEFINES"
[ -e "$APP" ] || { echo "ERROR: build output not found: $APP"; exit 1; }

# ── Device ───────────────────────────────────────────────────────────────────────────────────
if [ "$PLATFORM" = android ]; then
  adb get-state >/dev/null 2>&1 || { echo "ERROR: no booted Android emulator/device (adb devices)"; exit 1; }
  adb shell settings put global hide_error_dialogs 1 >/dev/null 2>&1 || true
fi

# A leftover Maestro driver / adb forward from an interrupted run makes the next one die with
# "DeviceServerDied … UNAVAILABLE"; Maestro re-pushes the driver on demand.
reset_maestro() {
  if [ "$PLATFORM" = android ]; then
    adb forward --remove-all >/dev/null 2>&1 || true
    adb uninstall dev.mobile.maestro >/dev/null 2>&1 || true
    adb uninstall dev.mobile.maestro.test >/dev/null 2>&1 || true
  else
    pkill -f 'XCTestRunner|WebDriverAgent' >/dev/null 2>&1 || true
  fi
}
reset_maestro

if [ "$PLATFORM" = ios ]; then
  DEVICE="${DEVICE:-$(xcrun simctl list devices booted | grep -oiE '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}' | head -1)}"
  [ -n "$DEVICE" ] || { echo "ERROR: no booted iOS simulator (set DEVICE=<udid> or boot one)"; exit 1; }
  echo "-- simulator $DEVICE"
  export MAESTRO_DRIVER_STARTUP_TIMEOUT="${MAESTRO_DRIVER_STARTUP_TIMEOUT:-120000}"
fi

reinstall() {
  if [ "$PLATFORM" = android ]; then
    adb uninstall "$APP_ID" >/dev/null 2>&1 || true
    adb install -t "$APP" >/dev/null
  else
    xcrun simctl uninstall "$DEVICE" "$APP_ID" >/dev/null 2>&1 || true
    xcrun simctl install "$DEVICE" "$APP"
  fi
}

mae() {
  if [ "$PLATFORM" = ios ]; then maestro --device "$DEVICE" test -e APP_ID="$APP_ID" -e LINK_URL="$LINK_URL" "$@"
  else maestro test -e APP_ID="$APP_ID" -e LINK_URL="$LINK_URL" "$@"; fi
}

# ── Android deferred staging: real click → lt_click → fake Play referrer ─────────────────────────
android_click_token() {
  local redirect token code waited=0
  redirect="$(curl -sS -o /dev/null -A "$ANDROID_UA" -w '%{redirect_url}' "$LINK_URL")" || return 1
  token="$(printf '%s' "$redirect" | grep -oE 'lt_click(%3D|=)[0-9a-f]{32}' | head -1 | grep -oE '[0-9a-f]{32}$' || true)"
  [ -n "$token" ] || { echo "   no lt_click in the redirect for $LINK_URL" >&2; return 1; }
  # Wait until the backend knows the click (the key goes through a stdin config, not argv).
  while [ "$waited" -lt "$CLICK_WAIT" ]; do
    code="$(printf 'header = "X-API-Key: %s"\n' "$LINKTRAIL_KEY" \
      | curl -sS -o /dev/null -w '%{http_code}' --config - "$BACKEND_URL/v1/events/click/$token" 2>/dev/null || true)"
    [ "$code" = 200 ] && { printf '%s' "$token"; return 0; }
    sleep 2; waited=$((waited + 2))
  done
  echo "   click not visible to this key after ${CLICK_WAIT}s (last status ${code:-none})" >&2
  return 1
}

reset_props() {
  [ "$PLATFORM" = android ] && adb shell setprop debug.linktrail.referrer "''" >/dev/null 2>&1 || true
}

# run_once <flow>: one attempt, including staging and the backend check.
run_once() {
  local flow="$1" token=""
  reinstall
  case "$flow" in
    deferred_*)
      if [ "$PLATFORM" = android ]; then
        token="$(android_click_token)" || return 1
        adb shell setprop debug.linktrail.referrer "lt_click=$token"
      else
        printf '' | xcrun simctl pbcopy "$DEVICE"
        mae "$FLOWS_DIR/ios/safari_click.yaml" || return 1
        token="$({ xcrun simctl pbpaste "$DEVICE" 2>/dev/null || true; } | grep -oE 'lt_click=[0-9a-fA-F]{32}' | head -1 | cut -d= -f2 || true)"
        [ -n "$token" ] || { echo "   no lt_click token on the clipboard after Safari" >&2; return 1; }
      fi
      echo "   click staged (${token:0:8}…)" ;;
    reengagement)
      if [ "$PLATFORM" = android ]; then
        # Approve the link host so the https link opens the app, not the browser (Android 12+).
        local host; host="$(printf '%s' "$LINK_URL" | sed -E 's#^https?://([^/]+).*#\1#')"
        adb shell pm set-app-links-user-selection --user 0 --package "$APP_ID" true "$host" >/dev/null 2>&1 || true
      fi ;;
  esac
  mae "$FLOWS_DIR/$flow.yaml" || { reset_props; return 1; }
  reset_props
  case "$flow" in
    deferred_allow) verify_click allow "$token" ;;
    deferred_deny)  verify_click deny "$token" ;;
  esac
}

# ── Run ──────────────────────────────────────────────────────────────────────────────────────
FAIL=0; PASSED=""; SKIPPED=""
for flow in $FLOWS; do
  if is_real "$flow" && [ $HAVE_KEY = 0 ]; then SKIPPED="$SKIPPED $flow"; continue; fi
  if [ "$PLATFORM" = android ] && [[ "$flow" == deferred_* ]] && ! android_has_fake_referrer; then
    warn "$flow skipped on Android: the pinned io.linktrail:sdk has no debug referrer override yet (needs > 0.0.5)"
    SKIPPED="$SKIPPED $flow"; continue
  fi
  ok=0
  for attempt in $(seq 1 "$RETRIES"); do
    echo "==> $PLATFORM · $flow (attempt $attempt/$RETRIES)"
    if run_once "$flow"; then ok=1; break; fi
    echo "   attempt failed; resetting the Maestro driver"
    reset_maestro; sleep 3
  done
  if [ $ok = 1 ]; then PASSED="$PASSED $flow"; else echo "!! FAILED: $flow"; FAIL=1; fi
done

[ $HAVE_KEY = 0 ] && note "LINKTRAIL_KEY is not set: real flows skipped on $PLATFORM (the local consent flows still ran)"
echo "==> passed:${PASSED:- none}"
echo "==> skipped:${SKIPPED:- none}"
[ $FAIL = 0 ] || { echo "==> some $PLATFORM e2e flows failed"; exit 1; }
echo "==> $PLATFORM e2e OK"
