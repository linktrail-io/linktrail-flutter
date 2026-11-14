# shellcheck shell=bash
#
# Backend checks for the real rows, sourced by e2e/run.sh. Polls the private endpoint
# GET /v1/e2e/clicks/<lt_click token> (header X-E2E-Token; LinkTrail contract e2e-verify-endpoint)
# for the row's own click only, never a global count, and judges each response with
# e2e/e2e-verify.py (the rules for every mode are there).
#   allow modes poll until the response matches; deny modes hold the whole window, so a late install
#   or open still shows. A field the backend lacks, a fraud flag or a wrong link type stops at once.
# Without E2E_TOKEN the check is skipped (VERIFY_STATUS=skipped); E2E_VERIFY_REQUIRED=1 makes that a
# failure. Neither the secret nor the full click token is ever printed.

VERIFY_BASE="${VERIFY_BASE:-https://backend.linktrail.io}"
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-15}"
VERIFY_PY="${VERIFY_PY:-$(dirname "${BASH_SOURCE[0]}")/e2e-verify.py}"

# shellcheck disable=SC2034 # VERIFY_* are read by the caller (e2e/run.sh)
# verify_backend <mode> <token> [e2e-verify.py check options…]
# Sets VERIFY_STATUS (ok | fail | skipped), VERIFY_DETAIL (one line) and VERIFY_CHECKS (CHECK lines);
# the last 200 body is kept in $VERIFY_LAST (the next step's baseline). Returns non-zero on fail.
verify_backend() {
  local mode="$1" token="$2"; shift 2
  local deadline body code out status="" detail="no response" checks=""
  VERIFY_STATUS=""; VERIFY_DETAIL=""; VERIFY_CHECKS=""
  rm -f "${VERIFY_LAST:?}"
  if [ -z "${E2E_TOKEN:-}" ]; then
    if [ "${E2E_VERIFY_REQUIRED:-0}" = "1" ]; then
      VERIFY_STATUS=fail; VERIFY_DETAIL="E2E_TOKEN is not set"; echo "   VERIFY FAIL ($mode): $VERIFY_DETAIL"; return 1
    fi
    VERIFY_STATUS=skipped; VERIFY_DETAIL="not checked: E2E_TOKEN not set"; echo "   VERIFY SKIP ($mode): $VERIFY_DETAIL"; return 0
  fi
  [ -n "$token" ] || { VERIFY_STATUS=fail; VERIFY_DETAIL="no lt_click token was captured for this row"; echo "   VERIFY FAIL ($mode): $VERIFY_DETAIL"; return 1; }
  deadline=$(( $(date +%s) + VERIFY_TIMEOUT ))
  body="$(mktemp)"
  while :; do
    # The secret reaches curl through a stdin config, so it never appears in argv, `ps` or the log.
    code="$(printf 'header = "X-E2E-Token: %s"\n' "$E2E_TOKEN" \
      | curl -sS -o "$body" -w '%{http_code}' --max-time 10 --config - "$VERIFY_BASE/v1/e2e/clicks/$token" 2>/dev/null || true)"
    if [ "$code" = 404 ]; then
      rm -f "$body"
      VERIFY_STATUS=fail
      VERIFY_DETAIL="404 for click ${token:0:8}…: the endpoint is off, X-E2E-Token is wrong, or the app id is not in the backend's E2E_APP_IDENTIFIERS"
      echo "   VERIFY FAIL ($mode): $VERIFY_DETAIL"; return 1
    fi
    if [ "$code" = 200 ]; then
      out="$(python3 -I "$VERIFY_PY" check --mode "$mode" --body "$body" "$@" 2>/dev/null)" || out=$'bad\ne2e-verify.py failed'
      status="$(sed -n 1p <<< "$out")"; detail="$(sed -n 2p <<< "$out")"; checks="$(grep '^CHECK' <<< "$out" || true)"
      cp "$body" "$VERIFY_LAST"
      case "$status" in missing|fail) break ;; esac
      if [[ "$mode" == *allow && "$status" == ok ]]; then break; fi
      if [[ "$mode" == *deny && "$status" != ok ]]; then break; fi
    else
      detail="HTTP ${code:-000}"
    fi
    [ "$(date +%s)" -ge "$deadline" ] && break
    sleep 2
  done
  rm -f "$body"
  VERIFY_CHECKS="$checks"
  VERIFY_DETAIL="click ${token:0:8}… $detail"
  if [ "$status" = ok ]; then VERIFY_STATUS=ok; echo "   VERIFY OK ($mode): $VERIFY_DETAIL"; return 0; fi
  VERIFY_STATUS=fail
  echo "   VERIFY FAIL ($mode) after ${VERIFY_TIMEOUT}s: $VERIFY_DETAIL"
  return 1
}
