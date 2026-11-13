#!/usr/bin/env bash
#
# Machine-wide lock around the simulator part of the E2E job (.github/workflows/e2e.yml).
#
# Several self-hosted runners are registered on the same Mac and they share one CoreSimulator device
# set, so two E2E jobs on different runners would shut each other's simulator down mid-flow. A GitHub
# concurrency group could serialise them, but a group holds only ONE pending job: a third PR waiting
# for e2e cancels the second. This lock serialises on the machine instead, so any number of jobs can
# wait their turn and none is cancelled.
#
#   acquire            wait for the lock, then print the PID of the process holding it (stdout).
#                      Progress goes to stderr. Exit 1 if it is not free within E2E_LOCK_TIMEOUT.
#   release <pid>      let go of the lock held by <pid>. A no-op for an empty, dead or foreign PID.
#
# The lock is a flock(2) held by a small background perl process (macOS has no flock(1)). The kernel
# drops it the moment that process exits, so it cannot go stale: the holder exits on `release`, when
# the job's Runner.Worker goes away (cancelled, crashed or finished without reaching `release`), when
# the runner kills the job's orphan processes, or after E2E_LOCK_MAX_HOLD seconds as a last resort.
#
# Env (all optional):
#   E2E_LOCK_FILE       default ~/.linktrail-e2e-simulators.lock. Per user on purpose: simulators
#                       belong to a user, so that is exactly the set of jobs that can collide.
#   E2E_LOCK_TIMEOUT    seconds to wait before giving up (default 5400 = 90 min).
#   E2E_LOCK_MAX_HOLD   seconds after which the holder lets go regardless (default 10800 = 3 h).
#   E2E_LOCK_WATCH_PID  release when this PID exits. Default: the Runner.Worker this script runs
#                       under, found by walking up the process tree. Set it to 0 to disable.
#   E2E_LOCK_OWNER      text written into the lock file so waiters can see who holds it.
set -uo pipefail

LOCK="${E2E_LOCK_FILE:-$HOME/.linktrail-e2e-simulators.lock}"
TIMEOUT="${E2E_LOCK_TIMEOUT:-5400}"
MAX_HOLD="${E2E_LOCK_MAX_HOLD:-10800}"
HOLDER_NAME="linktrail-e2e-lock-holder"

usage() { echo "usage: $0 acquire | release <pid>" >&2; exit 2; }
log() { echo "e2e-sim-lock: $*" >&2; }

# The Runner.Worker this shell runs under, or nothing outside GitHub Actions.
runner_worker_pid() {
  local pid=$$ ppid comm _
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -n "$ppid" ] && [ "$ppid" != 0 ] && [ "$ppid" != 1 ] || return 0
    comm="$(ps -o comm= -p "$ppid" 2>/dev/null)"
    case "$comm" in *Runner.Worker*) echo "$ppid"; return 0 ;; esac
    pid="$ppid"
  done
}

is_holder() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || return 1
  case "$(ps -o command= -p "$1" 2>/dev/null)" in "$HOLDER_NAME"*) return 0 ;; *) return 1 ;; esac
}

acquire() {
  local watch="${E2E_LOCK_WATCH_PID-}"
  if [ -z "$watch" ]; then
    watch="$(runner_worker_pid)"
    if [ -z "$watch" ]; then
      [ "${GITHUB_ACTIONS:-}" = true ] && log "warning: Runner.Worker not found; the lock is released by 'release', orphan cleanup or after ${MAX_HOLD}s"
      watch=0
    fi
  fi
  local owner="${E2E_LOCK_OWNER:-${GITHUB_REPOSITORY:-local} run ${GITHUB_RUN_ID:-?} (${GITHUB_REF:-?}) on ${RUNNER_NAME:-$(hostname)}}"
  local ready
  ready="$(mktemp "${TMPDIR:-/tmp}/e2e-sim-lock.XXXXXX")" || { log "mktemp failed"; return 1; }
  rm -f "$ready"

  # stdio goes to /dev/null: the caller reads our stdout through $(...), which would otherwise wait
  # for the background holder to close it, i.e. forever.
  perl -e '
    use strict; use warnings; use Fcntl qw(:flock O_RDWR O_CREAT); use IO::Handle;
    my ($lock, $ready, $watch, $maxhold, $owner, $name) = @ARGV;
    $0 = "$name $lock";   # shows in ps which lock this process holds
    sysopen(my $fh, $lock, O_RDWR | O_CREAT, 0644) or die "open $lock: $!";
    flock($fh, LOCK_EX) or die "flock $lock: $!";
    # The job that asked may have been cancelled while we waited: do not sit on the lock for it.
    exit 0 if $watch && !kill(0, $watch);
    my $done = sub { truncate($fh, 0); exit 0 };
    $SIG{TERM} = $SIG{INT} = $SIG{HUP} = $done;
    truncate($fh, 0); seek($fh, 0, 0); print $fh "$owner\n"; $fh->flush;
    open(my $r, ">", $ready) or die "open $ready: $!"; print $r "locked\n"; close $r;
    my $end = time + $maxhold;
    while (time < $end) { last if $watch && !kill(0, $watch); sleep 1 }
    $done->();
  ' "$LOCK" "$ready" "$watch" "$MAX_HOLD" "$owner" "$HOLDER_NAME" </dev/null >/dev/null 2>&1 &
  local holder=$!

  local start=$SECONDS last_note=$((SECONDS - 55)) holding   # first note after ~5s, not before the holder tried
  while :; do
    if [ -s "$ready" ]; then
      rm -f "$ready"
      log "acquired $LOCK after $((SECONDS - start))s (holder pid $holder)"
      echo "$holder"
      return 0
    fi
    if ! kill -0 "$holder" 2>/dev/null; then
      rm -f "$ready"
      log "the lock holder exited before getting $LOCK"
      return 1
    fi
    if [ $((SECONDS - start)) -ge "$TIMEOUT" ]; then
      kill "$holder" 2>/dev/null; rm -f "$ready"
      log "timed out after ${TIMEOUT}s waiting for $LOCK (held by: $(head -1 "$LOCK" 2>/dev/null))"
      return 1
    fi
    if [ $((SECONDS - last_note)) -ge 60 ]; then
      holding="$(head -1 "$LOCK" 2>/dev/null)"
      log "waiting for $LOCK — held by: ${holding:-another job}"
      last_note=$SECONDS
    fi
    sleep 1
  done
}

release() {
  local pid="${1:-}"
  if ! is_holder "$pid"; then
    [ -n "$pid" ] && log "pid $pid is not a lock holder (already released?); nothing to do"
    return 0
  fi
  kill "$pid" 2>/dev/null
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
  kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
  log "released (holder pid $pid)"
  return 0
}

case "${1:-}" in
  acquire) [ $# -eq 1 ] || usage; acquire ;;
  release) [ $# -le 2 ] || usage; release "${2:-}" ;;
  *) usage ;;
esac
