#!/usr/bin/env bash
# Install a pinned CocoaPods for this CI job only, into $RUNNER_TEMP, on a shared self-hosted Mac.
#
#   COCOAPODS_VERSION=1.16.2 bash scripts/ci/cocoapods.sh
#
# Nothing global: the gems, `pod` and CocoaPods' home dir (CP_HOME_DIR) all live in RUNNER_TEMP, and
# GEM_HOME / GEM_PATH / CP_HOME_DIR / PATH are exported to the later steps through $GITHUB_ENV and
# $GITHUB_PATH. The system Ruby (2.6) is too old for CocoaPods' dependencies, so it runs on Homebrew's
# Ruby: the `ruby` formula when installed, else the portable Ruby Homebrew ships for itself.
set -euo pipefail

COCOAPODS_VERSION="${COCOAPODS_VERSION:-1.16.2}"
: "${RUNNER_TEMP:?RUNNER_TEMP is not set}"

BREW="$(command -v brew || true)"
for c in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [ -n "$BREW" ] && break
  [ -x "$c" ] && BREW="$c"
done
[ -n "$BREW" ] || { echo "::error::Homebrew not found on this runner; it provides the Ruby CocoaPods runs on."; exit 1; }

RUBY_BIN=""
for d in "$("$BREW" --prefix ruby 2>/dev/null || true)/bin" "$("$BREW" --repository)/Library/Homebrew/vendor/portable-ruby/current/bin"; do
  if [ -x "$d/ruby" ] && "$d/ruby" -e 'exit(RUBY_VERSION >= "3.1" ? 0 : 1)'; then RUBY_BIN="$d"; break; fi
done
[ -n "$RUBY_BIN" ] || { echo "::error::No Ruby >= 3.1 from Homebrew on this runner (brew install ruby, or run any brew command once to fetch its portable Ruby)."; exit 1; }

GEMS="$RUNNER_TEMP/cocoapods-gems"
rm -rf "$GEMS" "$RUNNER_TEMP/cocoapods-home"
GEM_HOME="$GEMS" GEM_PATH="$GEMS" "$RUBY_BIN/gem" install --no-document --bindir "$GEMS/bin" "cocoapods:$COCOAPODS_VERSION"
if [ -n "${GITHUB_ENV:-}" ]; then
  { echo "GEM_HOME=$GEMS"; echo "GEM_PATH=$GEMS"; echo "CP_HOME_DIR=$RUNNER_TEMP/cocoapods-home"; } >> "$GITHUB_ENV"
fi
if [ -n "${GITHUB_PATH:-}" ]; then
  { echo "$GEMS/bin"; echo "$RUBY_BIN"; } >> "$GITHUB_PATH"
fi
echo "CocoaPods $COCOAPODS_VERSION on Ruby $("$RUBY_BIN/ruby" -e 'print RUBY_VERSION') ($RUBY_BIN)"
