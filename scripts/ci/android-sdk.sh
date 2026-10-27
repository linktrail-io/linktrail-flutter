#!/usr/bin/env bash
# Make the Android SDK packages a CI job needs available on a shared self-hosted Mac.
#
#   bash scripts/ci/android-sdk.sh <package>...      e.g. platform-tools "platforms;android-34"
#
# SDK: $ANDROID_HOME, else $ANDROID_SDK_ROOT, else ~/Library/Android/sdk (where Flutter and
# Android Studio put it). Packages already there are reused; missing ones are installed with a pinned
# cmdline-tools. The SDK is a versioned store (every package lives under its own versioned path), so
# sharing it between jobs is like sharing a tool cache: each job still names the exact versions it
# builds with. Installs run under a machine-wide lock, so two jobs never run sdkmanager over the
# same SDK at once. Nothing outside the SDK directory is touched.
#
# In GitHub Actions it exports ANDROID_HOME / ANDROID_SDK_ROOT and puts platform-tools on PATH.
set -euo pipefail

CMDLINE_TOOLS_ZIP="commandlinetools-mac-11076708_latest.zip"   # cmdline-tools 12.0, same as the Android SDK repo
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
LOCK="${ANDROID_SDK_LOCK_FILE:-$HOME/.linktrail-android-sdk.lock}"

LOCKED=0
[[ "${1:-}" == --locked ]] && { LOCKED=1; shift; }
[[ $# -gt 0 ]] || { echo "usage: $0 <sdk package>..." >&2; exit 2; }

missing() {
  local pkg out=()
  for pkg in "$@"; do
    # "platforms;android-34" lives in $SDK/platforms/android-34; every package has a package.xml.
    [[ -f "$SDK/${pkg//;//}/package.xml" ]] || out+=("$pkg")
  done
  printf '%s\n' ${out[@]+"${out[@]}"}
}

install_missing() {
  local todo=()
  while IFS= read -r pkg; do [[ -n "$pkg" ]] && todo+=("$pkg"); done < <(missing "$@")
  if [[ ${#todo[@]} -eq 0 ]]; then
    echo "==> Android SDK $SDK: all packages present"
    return 0
  fi
  local sdkmanager="$SDK/cmdline-tools/latest/bin/sdkmanager"
  if [[ ! -x "$sdkmanager" ]]; then
    echo "==> installing the command-line tools into $SDK"
    local tmp
    tmp="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/android-cmdline.XXXXXX")"
    curl -fsSL --retry 3 -o "$tmp/tools.zip" "https://dl.google.com/android/repository/$CMDLINE_TOOLS_ZIP"
    unzip -q "$tmp/tools.zip" -d "$tmp"
    mkdir -p "$SDK/cmdline-tools"
    rm -rf "$SDK/cmdline-tools/latest"
    mv "$tmp/cmdline-tools" "$SDK/cmdline-tools/latest"
    rm -rf "$tmp"
  fi
  yes | "$sdkmanager" --sdk_root="$SDK" --licenses >/dev/null 2>&1 || true
  echo "==> installing into $SDK: ${todo[*]}"
  "$sdkmanager" --sdk_root="$SDK" --install "${todo[@]}"
}

# Re-entered with the lock held: install, then return to the caller, which does the exports.
if [[ $LOCKED -eq 1 ]]; then
  install_missing "$@"
  exit 0
fi

mkdir -p "$SDK"
if [[ -n "$(missing "$@")" ]]; then
  # macOS has no flock(1): perl takes the lock and keeps the fd open across exec into this script,
  # so it is released the moment the install finishes or dies.
  echo "==> waiting for the Android SDK lock ($LOCK)"
  ANDROID_HOME="$SDK" perl -MFcntl=:flock -e '
    $^F = 255;   # keep the lock fd open across exec
    open(my $fh, ">>", shift) or die "open lock: $!";
    flock($fh, LOCK_EX) or die "flock: $!";
    exec @ARGV or die "exec: $!";
  ' "$LOCK" bash "$0" --locked "$@"
fi

[[ -n "${GITHUB_ENV:-}" ]] && { echo "ANDROID_HOME=$SDK"; echo "ANDROID_SDK_ROOT=$SDK"; } >> "$GITHUB_ENV"
[[ -n "${GITHUB_PATH:-}" ]] && echo "$SDK/platform-tools" >> "$GITHUB_PATH"
echo "==> Android SDK: $SDK"
