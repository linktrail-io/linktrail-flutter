#!/usr/bin/env bash
#
# Decide whether a change set is docs-only, so CI can skip its heavy steps on a pull request that
# cannot affect them. Reads changed paths (one per line, repo-relative, as printed by
# `git diff --name-only --no-renames`) on stdin and prints exactly one line:
#   docs_only=true    every path is documentation
#   docs_only=false   at least one path is not, or the list is empty (fail safe: run everything)
#
# Documentation means:  **/*.md   docs/**   LICENSE*   .github/ISSUE_TEMPLATE/**
#                       .github/pull_request_template.md
# Except (these look like docs but a build or test reads them, so they count as code):
#   CHANGELOG.md          flutter pub publish --dry-run validates it
#   LICENSE*              flutter pub publish --dry-run validates it
# Matching is case-sensitive on purpose: anything unexpected runs the full suite.
#
#   git diff --name-only --no-renames origin/main...HEAD | bash scripts/docs-only-changes.sh
#
# Exit codes: 0 always when stdin was read (the answer is on stdout), 2 usage error.
set -uo pipefail

if [ "$#" -ne 0 ]; then
  echo "usage: <paths on stdin> | bash scripts/docs-only-changes.sh" >&2
  exit 2
fi

seen=0
while IFS= read -r path || [ -n "$path" ]; do
  path="${path%$'\r'}"
  [ -z "$path" ] && continue
  seen=$((seen + 1))
  case "$path" in
    CHANGELOG.md)
      echo "not docs: $path (flutter pub publish --dry-run validates it)" >&2
      echo "docs_only=false"
      exit 0
      ;;
    LICENSE*)
      echo "not docs: $path (flutter pub publish --dry-run validates it)" >&2
      echo "docs_only=false"
      exit 0
      ;;
    *.md | docs/* | LICENSE* | .github/ISSUE_TEMPLATE/* | .github/pull_request_template.md) ;;
    *)
      echo "not docs: $path" >&2
      echo "docs_only=false"
      exit 0
      ;;
  esac
done

if [ "$seen" -eq 0 ]; then
  echo "no changed files listed; treating as a code change" >&2
  echo "docs_only=false"
  exit 0
fi

echo "all $seen changed file(s) are docs" >&2
echo "docs_only=true"
