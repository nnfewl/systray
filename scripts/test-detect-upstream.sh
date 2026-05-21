#!/usr/bin/env bash
# Smoke test for detect-upstream.sh. Run locally with: bash scripts/test-detect-upstream.sh
# Requires: gh CLI authenticated with read access to fyne-io/systray and nnfewl/systray.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

GITHUB_OUTPUT="$OUT" FORCE_REBUILD=false bash "$SCRIPT_DIR/detect-upstream.sh"

echo "--- captured outputs ---"
cat "$OUT"

grep -qE '^upstream-tag=v[0-9]+\.[0-9]+\.[0-9]+$'  "$OUT" || { echo "FAIL: upstream-tag missing or malformed"; exit 1; }
grep -qE '^upstream-version=[0-9]+\.[0-9]+\.[0-9]+$' "$OUT" || { echo "FAIL: upstream-version missing"; exit 1; }
grep -qE '^fork-tag=v[0-9]+\.[0-9]+\.[0-9]+-iconname$' "$OUT" || { echo "FAIL: fork-tag missing"; exit 1; }
grep -qE '^should-build=(true|false)$'              "$OUT" || { echo "FAIL: should-build missing"; exit 1; }
grep -qE '^today=[0-9]{4}-[0-9]{2}-[0-9]{2}$'       "$OUT" || { echo "FAIL: today missing"; exit 1; }

echo "OK"
