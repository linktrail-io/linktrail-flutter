# shellcheck shell=bash
#
# Backend check for the deferred flows, sourced by e2e/run.sh. Spec: the private endpoint
# GET /v1/e2e/clicks/<lt_click token> with header X-E2E-Token (LinkTrail contracts,
# e2e-verify-endpoint). It checks the flow's own click only, never a global count.
#   allow: installRecorded=true, attributed=true, matchType=click_token, installCount=1
#   deny:  installRecorded=false, installCount=0
# Without E2E_TOKEN the check is skipped with a note (E2E_VERIFY_REQUIRED=1 makes that a failure).
# Neither the secret nor the full click token is ever printed.

VERIFY_BASE="${VERIFY_BASE:-https://backend.linktrail.io}"
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-15}"

# judge <response.json> <allow|deny>: prints "PASS <fields>" or "WAIT <fields>".
judge() {
  python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1])); mode = sys.argv[2]
got = "installRecorded=%s attributed=%s matchType=%s installCount=%s" % (
    d.get("installRecorded"), d.get("attributed"), d.get("matchType"), d.get("installCount"))
if mode == "deny":
    ok = d.get("installRecorded") is False and d.get("installCount") == 0
else:
    ok = (d.get("installRecorded") is True and d.get("attributed") is True
          and d.get("matchType") == "click_token" and d.get("installCount") == 1)
print(("PASS " if ok else "WAIT ") + got)
' "$1" "$2" 2>/dev/null || echo "WAIT unparseable response"
}

# verify_click <allow|deny> <token>: polls until the expectation holds (allow) or for the whole
# window (deny, so a late install still shows up). Prints one VERIFY line; non-zero on failure.
verify_click() {
  local mode="$1" token="$2" deadline body code verdict="WAIT no response"
  if [ -z "${E2E_TOKEN:-}" ]; then
    if [ "${E2E_VERIFY_REQUIRED:-0}" = "1" ]; then echo "VERIFY FAIL: E2E_TOKEN is not set"; return 1; fi
    echo "VERIFY SKIP: E2E_TOKEN not set, backend check skipped"; return 0
  fi
  [ -n "$token" ] || { echo "VERIFY FAIL: no lt_click token was captured for this flow"; return 1; }
  deadline=$(( $(date +%s) + VERIFY_TIMEOUT ))
  body="$(mktemp)"
  while :; do
    # The secret reaches curl through a stdin config, so it never appears in argv, `ps` or the log.
    code="$(printf 'header = "X-E2E-Token: %s"\n' "$E2E_TOKEN" \
      | curl -sS -o "$body" -w '%{http_code}' --max-time 10 --config - "$VERIFY_BASE/v1/e2e/clicks/$token" 2>/dev/null || true)"
    case "$code" in
      404)
        rm -f "$body"
        echo "VERIFY FAIL: 404 for click ${token:0:8}… — the endpoint is off, the X-E2E-Token is wrong, or this app id is not in the backend's E2E_APP_IDENTIFIERS"
        return 1 ;;
      200)
        verdict="$(judge "$body" "$mode")"
        if [ "$mode" = allow ] && [[ "$verdict" == PASS* ]]; then break; fi
        if [ "$mode" = deny ] && [[ "$verdict" == WAIT* ]]; then break; fi ;;
      *) verdict="WAIT HTTP ${code:-000}" ;;
    esac
    [ "$(date +%s)" -ge "$deadline" ] && break
    sleep 2
  done
  rm -f "$body"
  if [[ "$verdict" == PASS* ]]; then echo "VERIFY OK ($mode): click ${token:0:8}… ${verdict#PASS }"; return 0; fi
  echo "VERIFY FAIL ($mode): click ${token:0:8}… after ${VERIFY_TIMEOUT}s — ${verdict#WAIT }"
  return 1
}
