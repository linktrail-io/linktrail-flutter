#!/usr/bin/env bash
# Maestro e2e for the LinkTrail Flutter plugin, driven against the example app built from this
# checkout (the plugin is a path dependency, so the Dart and native bridge code under test is the
# local source; the native SDKs come from the versions the plugin pins). The rows are the native
# SDKs' e2e rows, run through the plugin (see TESTING.md):
#   e2e/e2e-env.json    the ONE place for hosts, slugs and backend URLs, per environment
#   e2e/e2e-flows.json  the ONE table of rows (which flow, which link slot, which checks)
#   e2e/e2e-env.py      resolves both with the run's choices into the plan this script runs
#   e2e/e2e-verify.py   the backend rules (verify.sh polls the private verify endpoint with it)
#
# Usage:
#   bash e2e/run.sh android [row …]    # a booted emulator/device (adb)
#   bash e2e/run.sh ios [row …]        # a booted simulator (DEVICE=<udid> to pick one)
# A row is a flow name from e2e/e2e-flows.json (with its link-type rows) or one <flow>__<type> row.
# Default: every row.
#
# Rows:
#   local          consent_allow, consent_deny: no key, no click
#   deferred       a real click on the row's link, its token staged, a fresh install; backend install
#                  check (allow: recorded, attributed, click_token, 1 install, not fraud; deny: nothing),
#                  plus on the link-type rows (<flow>__<type>) linkType and the reward
#   problistic     a real click, NO token staged: only the backend's IP match can attribute
#   reengagement   a fresh install, consent, then the link opens the app (Android App Link; iOS
#                  handleDeepLink, an unsigned simulator build has no associated domains)
#   reopen         installed through the type's link first, then the link opens the installed app;
#                  backend openCount / installCount / earning against the install's baseline
#   reward         deferred install on the reward link, then the reward's events from the E2E panel;
#                  backend earning by the contract formula and the click's events
#   event          trackEvent with a value
# Real rows need LINKTRAIL_KEY; without it they are skipped with a notice. A link type or reward link
# the environment has no link for is skipped with a notice, never failed. A row whose app steps pass
# but whose backend check could not run (no E2E_TOKEN, a backend_checks toggle off) is reported as
# skipped with the reason, never as a pass.
#
# Env:
#   LINKTRAIL_KEY       SDK key for the selected environment's workspace. Reaches the build through a
#                       private temp file (--dart-define-from-file), never argv. Never printed.
#   E2E_TOKEN           X-E2E-Token for GET /v1/e2e/clicks/<token> (e2e/verify.sh). Never printed.
#   E2E_VERIFY_REQUIRED 1 = a missing E2E_TOKEN fails the rows instead of skipping their backend check.
#   LINKTRAIL_ENV       prod (default) | dev (test = dev), from e2e/e2e-env.json. dev points the app at
#                       the dev backend (Android: debug.linktrail.base; iOS: LINKTRAIL_BASE).
#   E2E_CUSTOM_LINK, E2E_SUBDOMAIN_LINK, E2E_CUSTOM_PROBLISTIC_LINK, E2E_SUBDOMAIN_PROBLISTIC_LINK
#                       override a link slot: a full URL on the environment's host, or a bare slug.
#   E2E_LINK_TYPES      link-type matrix: all (default) | none | comma list
#   E2E_EXPECT_VOUCHER  voucher the deferred rows must show (default in e2e/e2e-env.json)
#   RETRIES             attempts per row (default 2)
#   MIN_CTIT_WAIT       seconds between a click and the app launch (default 15: the backend flags an
#                       install under 10 s after its click as click injection)
#   E2E_RESULTS         results file (default build/e2e/results.txt); the summary goes to stdout and,
#                       in CI, to the job summary
set -euo pipefail
export PATH="$HOME/.maestro/bin:$PATH"

PLATFORM="${1:-}"; shift || true
case "$PLATFORM" in android|ios) ;; *) echo "usage: $0 android|ios [row …]" >&2; exit 2 ;; esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
E2E="$ROOT/e2e"
FLOWS_DIR="$E2E/flows"
EXAMPLE="$ROOT/example"
RETRIES="${RETRIES:-2}"
CLICK_WAIT="${CLICK_WAIT:-60}"
MIN_CTIT_WAIT="${MIN_CTIT_WAIT:-15}"
ANDROID_UA="Mozilla/5.0 (Linux; Android 15; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
SEP=$'\x1f'

if [ "$PLATFORM" = android ]; then APP_ID="io.linktrail.demo.store"; else APP_ID="io.linktrail.kickflipdemo"; fi

note() { if [ "${GITHUB_ACTIONS:-}" = true ]; then echo "::notice title=e2e::$*"; else echo "NOTE: $*"; fi; }

command -v maestro >/dev/null 2>&1 || { echo "ERROR: maestro not found (curl -Ls https://get.maestro.mobile.dev | bash)"; exit 1; }
command -v flutter >/dev/null 2>&1 || { echo "ERROR: flutter not found"; exit 1; }

# ── Targets and plan (fail fast on a bad choice, before the build) ───────────────────────────
targets="$(python3 -I "$E2E/e2e-env.py" resolve --format shell)" || exit 2
eval "$targets"
plan_out="$(python3 -I "$E2E/e2e-env.py" plan "$@")" || exit 2
ROWS=()
while IFS= read -r line; do [ -n "$line" ] && ROWS+=("$line"); done <<< "$plan_out"

VERIFY_BASE="$BACKEND_URL"
# shellcheck source=e2e/verify.sh
source "$E2E/verify.sh"

HAVE_KEY=0; [ -n "${LINKTRAIL_KEY:-}" ] && HAVE_KEY=1

WORK="$(mktemp -d)"; chmod 700 "$WORK"
DEFINES="$WORK/defines.json"
VERIFY_LAST="$WORK/verify-last.json"
cleanup() {
  rm -rf "$WORK"
  if [ "$PLATFORM" = android ]; then
    adb shell setprop debug.linktrail.referrer "''" >/dev/null 2>&1 || true
    adb shell setprop debug.linktrail.base "''" >/dev/null 2>&1 || true
  elif [ -n "${DEVICE:-}" ]; then
    xcrun simctl spawn "$DEVICE" launchctl unsetenv LINKTRAIL_BASE >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

RESULTS="${E2E_RESULTS:-$ROOT/build/e2e/results.txt}"
mkdir -p "$(dirname "$RESULTS")"; : > "$RESULTS"

# ── Build ────────────────────────────────────────────────────────────────────────────────────
write_defines() { # write_defines with-key|no-key
  python3 -I -c '
import json, os, sys
d = {"E2E": "true", "E2E_LINK_DOMAINS": os.environ.get("E2E_LINK_DOMAINS", "")}
if sys.argv[2] == "with-key" and os.environ.get("LINKTRAIL_KEY"): d["LINKTRAIL_API_KEY"] = os.environ["LINKTRAIL_KEY"]
json.dump(d, open(sys.argv[1], "w"))
' "$DEFINES" "$1"
  chmod 600 "$DEFINES"
}
export E2E_LINK_DOMAINS
write_defines with-key

echo "==> Building the example ($PLATFORM, environment $LINKTRAIL_ENV, backend $BACKEND_URL, SDK key: $([ $HAVE_KEY = 1 ] && echo set || echo not set))"
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
  XLOG="$WORK/xcodebuild.log"
  if ! xcodebuild -workspace "$EXAMPLE/ios/Runner.xcworkspace" -scheme Runner -configuration Debug \
      -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$EXAMPLE/build/e2e-derived" ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=NO \
      CODE_SIGNING_ALLOWED=NO build >"$XLOG" 2>&1; then
    echo "ERROR: iOS build failed:"; grep -E '(error|warning: .*fatal):' "$XLOG" | grep -v DART_DEFINES | head -20
    exit 1
  fi
  rm -f "$XLOG"
  # Rewrite the generated config without the key, so it does not stay on disk.
  write_defines no-key
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
  # dev: the DEBUG native SDK reads LINKTRAIL_BASE from its environment; apps launched on the
  # simulator inherit its launchd environment. prod: cleared (the SDK default).
  if [ -n "$BASE_OVERRIDE" ]; then xcrun simctl spawn "$DEVICE" launchctl setenv LINKTRAIL_BASE "$BASE_OVERRIDE"
  else xcrun simctl spawn "$DEVICE" launchctl unsetenv LINKTRAIL_BASE >/dev/null 2>&1 || true; fi
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

reset_props() {
  [ "$PLATFORM" = android ] || return 0
  adb shell setprop debug.linktrail.referrer "''" >/dev/null 2>&1 || true
  if [ -n "$BASE_OVERRIDE" ]; then adb shell setprop debug.linktrail.base "$BASE_OVERRIDE" >/dev/null 2>&1 || true
  else adb shell setprop debug.linktrail.base "''" >/dev/null 2>&1 || true; fi
}

# mae <flow.yaml> [-e KEY=value …]: one Maestro run with the row's environment.
mae() {
  local flow="$1"; shift
  local -a dev=()
  [ "$PLATFORM" = ios ] && dev=(--device "$DEVICE")
  if ! maestro ${dev[@]+"${dev[@]}"} test -e APP_ID="$APP_ID" -e LINK_URL="${ROW_URL:-}" \
      -e PATH_RE="${ROW_PATH_RE:-/.+}" -e CUSTOM_DATA_RE="${ROW_CUSTOM_RE:-customData: .*}" "$@" "$FLOWS_DIR/$flow"; then
    ROW_DETAIL="${ROW_DETAIL:+$ROW_DETAIL; }maestro $flow failed"
    return 1
  fi
}

# ── Click staging ────────────────────────────────────────────────────────────────────────────
# android_click <url>: a real click with an Android Chrome user agent; prints the lt_click token from
# the Play Store redirect once the backend knows the click (the key goes through a stdin config).
android_click() {
  local redirect token code waited=0
  redirect="$(curl -sS -o /dev/null -A "$ANDROID_UA" -w '%{redirect_url}' "$1")" || return 1
  token="$(printf '%s' "$redirect" | grep -oE 'lt_click(%3D|=)[0-9a-f]{32}' | head -1 | grep -oE '[0-9a-f]{32}$' || true)"
  if [ -z "$token" ]; then
    code="$(curl -sS -o /dev/null -A "$ANDROID_UA" -w '%{http_code}' "$1" || true)"
    [ "$code" = 404 ] && echo "   $LINKTRAIL_ENV link ${1##*/} not created (404)" >&2 \
      || echo "   no lt_click in the redirect for $1" >&2
    return 1
  fi
  while [ "$waited" -lt "$CLICK_WAIT" ]; do
    code="$(printf 'header = "X-API-Key: %s"\n' "$LINKTRAIL_KEY" \
      | curl -sS -o /dev/null -w '%{http_code}' --config - "$BACKEND_URL/v1/events/click/$token" 2>/dev/null || true)"
    [ "$code" = 200 ] && { printf '%s' "$token"; return 0; }
    sleep 2; waited=$((waited + 2))
  done
  echo "   click not visible to this key after ${CLICK_WAIT}s (last status ${code:-none})" >&2
  return 1
}

# ios_click: Safari opens ROW_URL; the interstitial puts lt_click=<token> on the clipboard. Prints it.
ios_click() {
  local token
  printf '' | xcrun simctl pbcopy "$DEVICE"
  mae ios/safari_click.yaml >&2 || return 1
  token="$({ xcrun simctl pbpaste "$DEVICE" 2>/dev/null || true; } | grep -oE 'lt_click=[0-9a-fA-F]{32}' | head -1 | cut -d= -f2 || true)"
  [ -n "$token" ] || { echo "   no lt_click token on the clipboard after Safari" >&2; return 1; }
  printf '%s' "$token"
}

# stage_click <staged|unstaged>: a real click on ROW_URL; sets TOKEN and CLICK_AT. staged hands the
# token to the fresh install (Android fake Play referrer; iOS leaves it on the clipboard for Paste);
# unstaged gives the install nothing (Android: no referrer; iOS: clipboard cleared).
stage_click() {
  TOKEN=""
  if [ "$PLATFORM" = android ]; then
    TOKEN="$(android_click "$ROW_URL")" || return 1
    [ "$1" = staged ] && adb shell setprop debug.linktrail.referrer "lt_click=$TOKEN"
  else
    TOKEN="$(ios_click)" || return 1
    [ "$1" = staged ] || printf '' | xcrun simctl pbcopy "$DEVICE"
  fi
  CLICK_AT=$SECONDS
  echo "   click staged=$1 (${TOKEN:0:8}…)"
}

# wait_ctit: returns once MIN_CTIT_WAIT has passed since the click.
wait_ctit() {
  local left=$((MIN_CTIT_WAIT - (SECONDS - CLICK_AT)))
  if [ "$left" -gt 0 ]; then sleep "$left"; fi
}

approve_hosts() {
  [ "$PLATFORM" = android ] || return 0
  # Approve the link hosts so the https link opens the app, not the browser (Android 12+).
  adb shell pm set-app-links-user-selection --user 0 --package "$APP_ID" true "$SUBDOMAIN_HOST" "$CUSTOM_HOST" >/dev/null 2>&1 || true
}

# backend <mode> [check options…]: verify_backend for TOKEN with this environment's toggles; adds
# its CHECK lines to the row and records a skipped check as the row's reason.
backend() {
  local mode="$1"; shift
  verify_backend "$mode" "$TOKEN" --earning "$([ "$E2E_CHECK_EARNING" = 1 ] && echo on || echo off)" \
    --open-count "$([ "$E2E_CHECK_OPEN_COUNT" = 1 ] && echo on || echo off)" \
    --events "$([ "$E2E_CHECK_EVENTS" = 1 ] && echo on || echo off)" "$@"
  local rc=$?
  ROW_BACKEND="${ROW_BACKEND:+$ROW_BACKEND; }$mode: $VERIFY_STATUS"
  ROW_DETAIL="${ROW_DETAIL:+$ROW_DETAIL; }$VERIFY_DETAIL"
  if [ "$VERIFY_STATUS" = skipped ]; then ROW_UNCHECKED="$VERIFY_DETAIL"; fi
  local skipped; skipped="$(awk -F'\t' '$3 == "skipped" { print $2 ": " $4; exit }' <<< "$VERIFY_CHECKS")"
  [ -n "$skipped" ] && [ -z "$ROW_UNCHECKED" ] && ROW_UNCHECKED="$skipped"
  return $rc
}

lt_args() { [ -n "$ROW_LT" ] && printf '%s\n' --link-type "$ROW_LT" --rewarded "$E2E_REWARDED_LINK_TYPES"; }

# run_row: one attempt of the current row (ROW_* globals). Returns non-zero on failure.
run_row() {
  local -a lt=()
  local events_out status spec n expect
  ROW_BACKEND=""; ROW_DETAIL=""; ROW_UNCHECKED=""; TOKEN=""; CLICK_AT=$SECONDS
  while IFS= read -r a; do [ -n "$a" ] && lt+=("$a"); done < <(lt_args)
  reinstall
  reset_props
  case "$ROW_KIND" in
    deferred|reward|reopen) stage_click staged || { ROW_DETAIL="real click failed"; return 1; } ;;
    problistic)             stage_click unstaged || { ROW_DETAIL="real click failed"; return 1; } ;;
  esac
  case "$ROW_KIND" in deferred|reward|reopen|problistic) wait_ctit ;; esac
  case "$ROW_KIND" in reengagement|reopen) approve_hosts ;; esac

  case "$ROW_KIND" in
    local|event|reengagement)
      mae "$ROW_YAML" ;;
    deferred)
      mae "$ROW_YAML" || return 1
      backend "$ROW_CONSENT" ${lt[@]+"${lt[@]}"} ;;
    problistic)
      mae "$ROW_YAML" || return 1
      if [ "$ROW_CONSENT" = deny ]; then backend deny
      else ROW_BACKEND="n/a"; ROW_DETAIL="device lookup not checkable: the plugin exposes no SDK device id"; fi ;;
    reopen)
      # Step 1: install through the type's link (counted on allow, nothing on deny), backend baseline.
      mae "deferred_$ROW_CONSENT.yaml" || return 1
      backend "$ROW_CONSENT" ${lt[@]+"${lt[@]}"} || return 1
      cp "$VERIFY_LAST" "$WORK/baseline.json" 2>/dev/null || : > "$WORK/baseline.json"
      [ "$PLATFORM" = android ] && adb shell setprop debug.linktrail.referrer "''" >/dev/null 2>&1
      # Step 2: the same link opens the installed app.
      mae reopen.yaml -e CONSENT_TEXT="$([ "$ROW_CONSENT" = allow ] && echo granted || echo denied)" || return 1
      if [ "$VERIFY_STATUS" = ok ]; then backend "reopen_$ROW_CONSENT" --baseline "$WORK/baseline.json"; fi ;;
    reward)
      mae "$ROW_YAML" || return 1
      backend "$ROW_CONSENT" --link-type "$ROW_LT" --model "$ROW_MODEL" || return 1
      # The reward's terms come from the install's response: no E2E_TOKEN, nothing to send or check.
      [ "$VERIFY_STATUS" = ok ] || return 0
      cp "$VERIFY_LAST" "$WORK/baseline.json"
      events_out="$(python3 -I "$E2E/e2e-verify.py" plan-events --model "$ROW_MODEL" --body "$WORK/baseline.json" \
        --revenue-minor "$E2E_REVENUE_MINOR" --other-event "$E2E_OTHER_EVENT" --revenue-event "$E2E_REVENUE_EVENT")" || events_out="fail"
      status="$(sed -n 1p <<< "$events_out")"; spec="$(sed -n 3p <<< "$events_out")"; n="$(sed -n 4p <<< "$events_out")"
      if [ "$status" != ok ]; then ROW_DETAIL="$ROW_DETAIL; events not planned: $(sed -n 2p <<< "$events_out")"; return 1; fi
      echo "   sending $(sed -n 2p <<< "$events_out")"
      if [ "$ROW_CONSENT" = allow ]; then expect="requested $n sent $n attributed $n failed 0"
      else expect="requested $n sent 0 attributed 0 failed 0"; fi
      mae send_events.yaml -e EVENTS_SPEC="$spec" -e EXPECT_EVENTS="$expect" || return 1
      backend "events_$ROW_CONSENT" --baseline "$WORK/baseline.json" --model "$ROW_MODEL" \
        --revenue-minor "$E2E_REVENUE_MINOR" --other-event "$E2E_OTHER_EVENT" --revenue-event "$E2E_REVENUE_EVENT" ;;
    *)
      echo "   unknown row kind $ROW_KIND"; return 1 ;;
  esac
}

record() { # record <row> <result> <attempts> <link> <link type> <backend> <detail>
  local IFS="$SEP"; printf '%s\n' "$PLATFORM$SEP$*" >> "$RESULTS"
}

# ── Run ──────────────────────────────────────────────────────────────────────────────────────
[ -n "$E2E_LINK_TYPES_SKIPPED" ] && note "link types without a $LINKTRAIL_ENV link, skipped: $E2E_LINK_TYPES_SKIPPED (add a \"$LINKTRAIL_ENV\" entry to link_types in e2e/e2e-env.json)"
FAIL=0; NO_KEY=0
for line in ${ROWS[@]+"${ROWS[@]}"}; do
  IFS="$SEP" read -r ROW ROW_YAML ROW_KIND ROW_CONSENT ROW_URL ROW_LT ROW_MODEL ROW_PATH_RE ROW_CUSTOM_RE ROW_SKIP <<< "$line"
  if [ -n "$ROW_SKIP" ]; then
    echo "==> $PLATFORM · $ROW: SKIPPED ($ROW_SKIP)"
    note "$ROW skipped: $ROW_SKIP"
    record "$ROW" skipped 0 "$ROW_URL" "$ROW_LT" "" "$ROW_SKIP"; continue
  fi
  if [ "$ROW_KIND" != local ] && [ $HAVE_KEY = 0 ]; then
    NO_KEY=1; record "$ROW" skipped 0 "$ROW_URL" "$ROW_LT" "" "LINKTRAIL_KEY not set"; continue
  fi
  ok=0
  for attempt in $(seq 1 "$RETRIES"); do
    echo "==> $PLATFORM · $ROW (attempt $attempt/$RETRIES)${ROW_URL:+ · $ROW_URL}"
    if run_row; then ok=1; break; fi
    echo "   attempt failed${ROW_DETAIL:+: $ROW_DETAIL}; resetting the Maestro driver"
    reset_maestro; sleep 3
  done
  reset_props
  if [ $ok = 1 ] && [ -n "$ROW_UNCHECKED" ]; then
    echo "   app steps passed; reported as skipped: $ROW_UNCHECKED"
    record "$ROW" skipped "$attempt" "$ROW_URL" "$ROW_LT" "$ROW_BACKEND" "app steps passed; $ROW_UNCHECKED"
  elif [ $ok = 1 ]; then
    record "$ROW" pass "$attempt" "$ROW_URL" "$ROW_LT" "${ROW_BACKEND:-n/a}" "$ROW_DETAIL"
  else
    echo "!! FAILED: $ROW"; FAIL=1
    record "$ROW" fail "$RETRIES" "$ROW_URL" "$ROW_LT" "$ROW_BACKEND" "$ROW_DETAIL"
  fi
done

[ $NO_KEY = 1 ] && note "LINKTRAIL_KEY is not set: real rows skipped on $PLATFORM (the local consent rows still ran)"
[ $HAVE_KEY = 1 ] && [ -z "${E2E_TOKEN:-}" ] && note "E2E_TOKEN is not set: rows whose point is the backend check are reported as skipped on $PLATFORM"

# ── Summary ──────────────────────────────────────────────────────────────────────────────────
summary() {
  local row result attempts link backend detail
  echo "### E2E · $PLATFORM · $LINKTRAIL_ENV ($BACKEND_URL)"
  echo
  echo "| Row | Result | Attempts | Link | Backend | Detail |"
  echo "| --- | --- | --- | --- | --- | --- |"
  while IFS="$SEP" read -r _ row result attempts link _ backend detail; do
    [ -n "$row" ] || continue
    # shellcheck disable=SC2016 # the backticks are Markdown code spans
    printf '| `%s` | %s | %s | %s | %s | %s |\n' "$row" "$result" "$attempts" "${link:-}" "${backend:-}" "$(printf '%s' "$detail" | tr '|' '/')"
  done < "$RESULTS"
  echo
  echo "passed $(grep -c "${SEP}pass${SEP}" "$RESULTS" || true), skipped $(grep -c "${SEP}skipped${SEP}" "$RESULTS" || true), failed $(grep -c "${SEP}fail${SEP}" "$RESULTS" || true)"
}
summary
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && summary >> "$GITHUB_STEP_SUMMARY"

[ $FAIL = 0 ] || { echo "==> some $PLATFORM e2e rows failed"; exit 1; }
echo "==> $PLATFORM e2e OK"
