#!/usr/bin/env bash
# Detect the newest upstream release tag and decide whether the pipeline
# needs to build. Writes outputs to $GITHUB_OUTPUT (or stdout if unset).
#
# Env:
#   FORCE_REBUILD  - "true" forces should-build=true even if fork tag exists.
#                    Default: "false".
#
# Outputs:
#   upstream-tag      e.g. v1.12.1
#   upstream-version  e.g. 1.12.1
#   fork-tag          e.g. v1.12.1-iconname
#   should-build      true|false
#   today             YYYY-MM-DD (UTC)

set -euo pipefail

UPSTREAM_REPO="fyne-io/systray"
FORK_REPO="${GITHUB_REPOSITORY:-nnfewl/systray}"
TAG_SUFFIX="-iconname"
FORCE_REBUILD="${FORCE_REBUILD:-false}"

latest_tag=$(
  gh api --paginate "repos/${UPSTREAM_REPO}/tags" --jq '.[].name' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -1
)

if [[ -z "$latest_tag" ]]; then
  echo "ERROR: no v* release tag found on ${UPSTREAM_REPO}" >&2
  exit 1
fi

upstream_version="${latest_tag#v}"
fork_tag="${latest_tag}${TAG_SUFFIX}"

echo "latest upstream tag: $latest_tag (version $upstream_version)"
echo "fork tag to publish: $fork_tag"

fork_tag_exists=false
if gh api "repos/${FORK_REPO}/git/ref/tags/${fork_tag}" >/dev/null 2>&1; then
  fork_tag_exists=true
  echo "fork tag $fork_tag already exists"
else
  echo "fork tag $fork_tag does not yet exist"
fi

should_build=false
if [[ "$fork_tag_exists" == "false" ]] || [[ "$FORCE_REBUILD" == "true" ]]; then
  should_build=true
fi

{
  echo "upstream-tag=${latest_tag}"
  echo "upstream-version=${upstream_version}"
  echo "fork-tag=${fork_tag}"
  echo "should-build=${should_build}"
  echo "today=$(date -u +%Y-%m-%d)"
} | tee -a "${GITHUB_OUTPUT:-/dev/stdout}"
