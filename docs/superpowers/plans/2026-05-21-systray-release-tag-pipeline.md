# Systray Release-Tag Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a GitHub Actions pipeline on `nnfewl/systray` that tracks new upstream release tags daily, rebases the `set-icon-name` patch branch onto each new tag, and publishes a `v<UPSTREAM>-iconname` fork tag for downstream `go.mod` pinning.

**Architecture:** Three-branch layout (`master` mirror, `set-icon-name` patches, `pipeline` infra) with a daily workflow (`detect-upstream → sync-fork → rebase-patches → verify`). Rebase conflicts surface as GitHub issues. No GH release. No build artifact.

**Tech Stack:** GitHub Actions, bash, `gh` CLI, `git`, `actions/checkout@v6`, `actions/setup-go@v5`.

**Reference spec:** `docs/superpowers/specs/2026-05-21-systray-release-tag-pipeline-design.md`

---

## File Structure

All new files land on the `pipeline` branch (already created locally with the spec).

```
.github/workflows/pipeline.yml         # the workflow
scripts/detect-upstream.sh             # tag detection + skip logic
scripts/test-detect-upstream.sh        # local smoke test (not run in CI)
README.md                              # pipeline branch's README (replaces upstream's)
```

The `master` branch remains a pure upstream mirror and is **not** edited by any task.
The `set-icon-name` branch is bootstrapped in Task 1 and only touched by Task 1.

---

## Task 1: Bootstrap `set-icon-name` patch branch

**Goal:** Create `set-icon-name` off the latest upstream tag (`v1.12.1`), apply the source modifications currently sitting at `/home/sparkvix/Github/Personal-patch/src/systray-custom/`, push to fork.

**Files:**
- Modify (via copy): every Go/XML/MD file under repo root and `internal/` that differs from `systray-custom`
- Branch: `set-icon-name` (new)

**Pre-checks:**

- [ ] **Step 1: Confirm working tree is clean and we're on `pipeline`**

Run:
```bash
git -C /home/sparkvix/Projects/testground/systray status
git -C /home/sparkvix/Projects/testground/systray branch --show-current
```
Expected: clean tree; current branch `pipeline`.

- [ ] **Step 2: Confirm upstream tag exists locally**

Run:
```bash
git -C /home/sparkvix/Projects/testground/systray tag -l v1.12.1
```
Expected output: `v1.12.1`. If empty: `git fetch origin --tags`.

- [ ] **Step 3: Inventory the diff so we know what we're about to commit**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
diff -rq . /home/sparkvix/Github/Personal-patch/src/systray-custom \
  2>/dev/null \
  | grep -v -E '\.git|PLAN-systray|docs/superpowers|^Only in '
```
Expected: a short list of "Files X and Y differ" lines (around 8 files). If unexpected files appear (e.g. `go.mod`), stop and review with the user before proceeding.

**Branch creation:**

- [ ] **Step 4: Create `set-icon-name` off v1.12.1**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
git checkout -b set-icon-name v1.12.1
```
Expected: `Switched to a new branch 'set-icon-name'`.

- [ ] **Step 5: Copy customized files in**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
SRC=/home/sparkvix/Github/Personal-patch/src/systray-custom
cp "$SRC/systray.go" systray.go
cp "$SRC/systray_unix.go" systray_unix.go
cp "$SRC/systray_menu_unix.go" systray_menu_unix.go
cp "$SRC/systray_darwin.m" systray_darwin.m
cp "$SRC/README.md" README.md
cp "$SRC/internal/StatusNotifierItem.xml" internal/StatusNotifierItem.xml
cp "$SRC/internal/generated/notifier/status_notifier_item.go" internal/generated/notifier/status_notifier_item.go
cp "$SRC/internal/generated/menu/dbus_menu.go" internal/generated/menu/dbus_menu.go
```
Expected: silent success. No errors about missing files.

- [ ] **Step 6: Verify the tree builds and tests**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
go build ./...
go test ./...
```
Expected: both commands exit 0. If build fails, the custom tree references symbols not present in v1.12.1 — stop and report to user.

- [ ] **Step 7: Commit**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
git add -A
git status
git commit -m "patch: add SetIconName and related theme-native tray icon changes

Patches applied on top of fyne-io/systray v1.12.1 to support
QIcon::fromTheme()-style icon resolution via the StatusNotifierItem
IconName D-Bus property, plus related Unix-side updates."
```
Expected: one commit on `set-icon-name`.

- [ ] **Step 8: Push set-icon-name and v1.12.1-iconname tag**

> **WAIT for user confirmation before pushing.** Pushing creates the long-lived branch on the fork.

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
git tag v1.12.1-iconname
git push origin set-icon-name
git push origin v1.12.1-iconname
```
Expected: both refs created on `origin`.

- [ ] **Step 9: Return to pipeline branch**

Run:
```bash
git -C /home/sparkvix/Projects/testground/systray checkout pipeline
```
Expected: `Switched to branch 'pipeline'`.

---

## Task 2: Add `scripts/detect-upstream.sh`

**Goal:** Detect newest upstream release tag and decide whether to build, writing outputs to `$GITHUB_OUTPUT`.

**Files:**
- Create: `scripts/detect-upstream.sh`
- Create: `scripts/test-detect-upstream.sh`

- [ ] **Step 1: Write the local smoke test first**

Create `scripts/test-detect-upstream.sh`:

```bash
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
```

Make it executable:
```bash
chmod +x /home/sparkvix/Projects/testground/systray/scripts/test-detect-upstream.sh
```

- [ ] **Step 2: Run the test to verify it fails (script doesn't exist yet)**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
bash scripts/test-detect-upstream.sh
```
Expected: fails with "No such file or directory: scripts/detect-upstream.sh".

- [ ] **Step 3: Write `scripts/detect-upstream.sh`**

Create `scripts/detect-upstream.sh`:

```bash
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
```

Make it executable:
```bash
chmod +x /home/sparkvix/Projects/testground/systray/scripts/detect-upstream.sh
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
bash scripts/test-detect-upstream.sh
```
Expected: prints captured outputs ending in `OK`. `upstream-tag` should be `v1.12.1` (or newer if upstream released since 2026-05-21). `should-build` will be `true` if Task 1 hasn't been pushed yet, `false` if it has.

- [ ] **Step 5: Commit**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
git add scripts/detect-upstream.sh scripts/test-detect-upstream.sh
git commit -m "scripts: detect newest upstream release tag

Mirrors MEGAsync's detect-upstream.sh shape but targets
fyne-io/systray's vX.Y.Z tags and checks the fork for an
existing vX.Y.Z-iconname tag to decide whether to build."
```

---

## Task 3: Add workflow skeleton with `detect-upstream` job

**Goal:** Workflow file that runs daily, dispatches manually, and has the detect job wired up.

**Files:**
- Create: `.github/workflows/pipeline.yml`

- [ ] **Step 1: Create `.github/workflows/pipeline.yml`**

```yaml
name: Pipeline

on:
  schedule:
    - cron: '0 6 * * *'
  workflow_dispatch:
    inputs:
      force_rebuild:
        description: 'Rebuild even if fork tag exists'
        type: boolean
        default: false

permissions:
  contents: write
  issues: write

concurrency:
  group: release-pipeline
  cancel-in-progress: false

env:
  UPSTREAM_REPO: fyne-io/systray

jobs:
  # -------------------------------------------------------------------
  # detect-upstream
  # -------------------------------------------------------------------
  detect-upstream:
    runs-on: ubuntu-24.04
    outputs:
      upstream-tag:     ${{ steps.detect.outputs.upstream-tag }}
      upstream-version: ${{ steps.detect.outputs.upstream-version }}
      fork-tag:         ${{ steps.detect.outputs.fork-tag }}
      should-build:     ${{ steps.detect.outputs.should-build }}
      today:            ${{ steps.detect.outputs.today }}
    steps:
      - uses: actions/checkout@v6
      - name: Detect latest upstream release tag
        id: detect
        env:
          GH_TOKEN: ${{ github.token }}
          FORCE_REBUILD: ${{ inputs.force_rebuild || 'false' }}
        run: bash scripts/detect-upstream.sh
      - name: Summary
        run: |
          {
            echo "### Upstream state"
            echo "| Tag | Version | Fork tag | Needs build? |"
            echo "|---|---|---|---|"
            echo "| \`${{ steps.detect.outputs.upstream-tag }}\` | ${{ steps.detect.outputs.upstream-version }} | \`${{ steps.detect.outputs.fork-tag }}\` | ${{ steps.detect.outputs.should-build }} |"
          } >> "$GITHUB_STEP_SUMMARY"
```

- [ ] **Step 2: Verify YAML syntax**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/pipeline.yml'))" && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Commit**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
git add .github/workflows/pipeline.yml
git commit -m "ci: scaffold pipeline workflow with detect-upstream job

Daily cron + workflow_dispatch with force_rebuild input. Detect job
calls scripts/detect-upstream.sh and exports outputs for downstream
jobs."
```

---

## Task 4: Add `sync-fork` job

**Goal:** When a new upstream tag exists, fast-forward `master` and push the tag to the fork.

**Files:**
- Modify: `.github/workflows/pipeline.yml` (append `sync-fork` job)

- [ ] **Step 1: Append the `sync-fork` job**

Append to `.github/workflows/pipeline.yml`:

```yaml
  # -------------------------------------------------------------------
  # sync-fork: fast-forward master + push the new upstream tag to fork
  # -------------------------------------------------------------------
  sync-fork:
    needs: detect-upstream
    if: needs.detect-upstream.outputs.should-build == 'true'
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
          token: ${{ github.token }}
      - name: Sync upstream master and tag to fork
        env:
          UPSTREAM_TAG: ${{ needs.detect-upstream.outputs.upstream-tag }}
        run: |
          git config user.email "systray-pipeline@local"
          git config user.name  "systray-pipeline"
          git remote add upstream "https://github.com/${{ env.UPSTREAM_REPO }}.git"
          git fetch upstream master --tags

          git push origin \
            "refs/remotes/upstream/master:refs/heads/master" \
            --force

          git push origin "refs/tags/${UPSTREAM_TAG}" --force
```

- [ ] **Step 2: Verify YAML syntax**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/pipeline.yml'))" && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Commit**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
git add .github/workflows/pipeline.yml
git commit -m "ci: add sync-fork job

Fast-forwards fork's master from upstream and pushes the newest
upstream release tag. Force-pushes are safe because master is a
pure mirror; tag force-push covers the upstream-re-tag edge case."
```

---

## Task 5: Add `rebase-patches` job with conflict-to-issue handling

**Goal:** Rebase `set-icon-name` onto the new tag; on success, push branch + fork tag; on conflict, open issue and fail.

**Files:**
- Modify: `.github/workflows/pipeline.yml` (append `rebase-patches` job)

- [ ] **Step 1: Append the `rebase-patches` job**

Append to `.github/workflows/pipeline.yml`:

```yaml
  # -------------------------------------------------------------------
  # rebase-patches: rebase set-icon-name onto new upstream tag,
  # push branch + v<UPSTREAM>-iconname tag. On conflict: open issue.
  # -------------------------------------------------------------------
  rebase-patches:
    needs: [detect-upstream, sync-fork]
    if: needs.detect-upstream.outputs.should-build == 'true'
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
          token: ${{ github.token }}
      - name: Rebase set-icon-name and publish fork tag
        env:
          UPSTREAM_TAG: ${{ needs.detect-upstream.outputs.upstream-tag }}
          FORK_TAG:     ${{ needs.detect-upstream.outputs.fork-tag }}
          GH_TOKEN:     ${{ github.token }}
        run: |
          git config user.email "systray-pipeline@local"
          git config user.name  "systray-pipeline"

          git fetch origin set-icon-name "${UPSTREAM_TAG}"
          git checkout set-icon-name

          if git rebase "${UPSTREAM_TAG}"; then
            git push origin set-icon-name --force-with-lease
            git tag --force "${FORK_TAG}"
            git push origin "${FORK_TAG}" --force
          else
            git rebase --abort
            gh issue create \
              --title "Rebase needed: set-icon-name onto ${UPSTREAM_TAG}" \
              --label "automation" \
              --body "$(cat <<EOF
          Automated rebase of \`set-icon-name\` onto \`${UPSTREAM_TAG}\` failed due to conflicts.

          ### Manual fix

          \`\`\`bash
          git fetch origin
          git checkout set-icon-name
          git rebase ${UPSTREAM_TAG}
          # resolve conflicts, then:
          git push origin set-icon-name --force-with-lease
          \`\`\`

          ### Re-run pipeline

          \`\`\`bash
          gh workflow run pipeline.yml --ref pipeline -f force_rebuild=true
          \`\`\`
          EOF
          )"
            exit 1
          fi
```

- [ ] **Step 2: Verify YAML syntax**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/pipeline.yml'))" && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Commit**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
git add .github/workflows/pipeline.yml
git commit -m "ci: add rebase-patches job with conflict-to-issue handling

Rebases set-icon-name onto the new upstream tag. On success,
force-pushes the branch and creates the v<UPSTREAM>-iconname tag.
On conflict, opens a labeled GH issue with manual fix instructions
and exits non-zero."
```

---

## Task 6: Add `verify` job

**Goal:** Confirm the patched tree at the fork tag builds and tests cleanly.

**Files:**
- Modify: `.github/workflows/pipeline.yml` (append `verify` job)

- [ ] **Step 1: Append the `verify` job**

Append to `.github/workflows/pipeline.yml`:

```yaml
  # -------------------------------------------------------------------
  # verify: build and test the patched tree at the new fork tag
  # -------------------------------------------------------------------
  verify:
    needs: [detect-upstream, rebase-patches]
    if: needs.detect-upstream.outputs.should-build == 'true'
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v6
        with:
          ref: ${{ needs.detect-upstream.outputs.fork-tag }}
          fetch-depth: 1
      - uses: actions/setup-go@v5
        with:
          go-version: 'stable'
      - name: Build
        run: go build ./...
      - name: Test
        run: go test ./...
```

- [ ] **Step 2: Verify YAML syntax**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/pipeline.yml'))" && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Commit**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
git add .github/workflows/pipeline.yml
git commit -m "ci: add verify job

Checks out the freshly published v<UPSTREAM>-iconname tag and runs
go build + go test as a post-rebase sanity check."
```

---

## Task 7: Replace pipeline branch README

**Goal:** The pipeline branch's README should describe the fork's purpose and the pipeline shape — not upstream's library docs.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace `README.md` on the `pipeline` branch**

Overwrite `README.md` with:

```markdown
# systray — SetIconName Fork

Automated fork of [fyne-io/systray](https://github.com/fyne-io/systray) that adds `SetIconName()` to the Linux StatusNotifierItem path, letting desktop environments resolve tray icons from the user's theme (Papirus, Tela, etc.) instead of receiving hardcoded pixmaps over D-Bus.

## How it works

```
detect-upstream → sync-fork → rebase-patches → verify
```

1. **Detect**: daily cron checks for new `vX.Y.Z` tags on `fyne-io/systray`.
2. **Sync**: fast-forwards fork's `master`, pushes the new upstream tag.
3. **Rebase**: rebases `set-icon-name` onto the new tag, publishes `vX.Y.Z-iconname`.
4. **Verify**: `go build ./...` + `go test ./...` at the new tag.

Rebase conflicts open a GitHub issue with manual-fix instructions.

## Branches

| Branch | Purpose |
|---|---|
| `pipeline` | Default. CI workflow + scripts. |
| `master` | Pure mirror of upstream `fyne-io/systray`. |
| `set-icon-name` | Patch branch — `SetIconName()` commits on top of upstream tag. |

## Tags

Fork tags use the suffix `-iconname`. For each upstream `vX.Y.Z`, the pipeline publishes `vX.Y.Z-iconname` pointing at `set-icon-name` rebased onto that tag.

## Downstream consumption

```
// go.mod
replace fyne.io/systray => github.com/nnfewl/systray v1.12.1-iconname
```

Bump the version line when a new upstream release lands.

## Manual rebuild

```bash
gh workflow run pipeline.yml --ref pipeline -f force_rebuild=true
```
```

- [ ] **Step 2: Commit**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
git add README.md
git commit -m "docs: pipeline-branch README describes the fork pipeline

Replaces the inherited upstream library README on the pipeline
branch only; master and set-icon-name keep upstream's README."
```

---

## Task 8: Push pipeline branch and dry-run the workflow

**Goal:** Push everything to the fork, set `pipeline` as default branch, trigger a manual run to confirm green.

> **Each step here writes to the live GitHub repo. Pause between steps and confirm with the user before pushing.**

- [ ] **Step 1: Push the `pipeline` branch**

Run:
```bash
cd /home/sparkvix/Projects/testground/systray
git push -u origin pipeline
```
Expected: branch pushed with all 7 commits.

- [ ] **Step 2: Set `pipeline` as default branch on GitHub**

Run:
```bash
gh repo edit nnfewl/systray --default-branch pipeline
```
Expected: `✓ Edited repository nnfewl/systray`.

- [ ] **Step 3: Trigger the pipeline manually**

Run:
```bash
gh workflow run pipeline.yml --ref pipeline
```
Expected: `✓ Created workflow_dispatch event for pipeline.yml at pipeline`.

- [ ] **Step 4: Watch the run**

Run:
```bash
sleep 5
gh run watch "$(gh run list --workflow=pipeline.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```
Expected:
- `detect-upstream` succeeds, reports `should-build=false` (because Task 1 already pushed `v1.12.1-iconname`).
- `sync-fork`, `rebase-patches`, `verify` are all skipped via the `should-build` gate.

If `should-build=true` instead (i.e. Task 1 didn't push the tag yet), the run will proceed all the way through and re-create `v1.12.1-iconname` from scratch — also a valid green path.

- [ ] **Step 5: Force-rebuild dry run**

Run:
```bash
gh workflow run pipeline.yml --ref pipeline -f force_rebuild=true
sleep 5
gh run watch "$(gh run list --workflow=pipeline.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```
Expected: full pipeline runs green end-to-end; `v1.12.1-iconname` tag is recreated, verify job passes.

- [ ] **Step 6: Confirm tag is on origin**

Run:
```bash
git -C /home/sparkvix/Projects/testground/systray fetch origin --tags
git -C /home/sparkvix/Projects/testground/systray tag -l 'v*-iconname'
```
Expected: `v1.12.1-iconname` present.

---

## Self-Review Notes

Coverage check against spec:

| Spec requirement | Task |
|---|---|
| Three-branch layout (`master`/`set-icon-name`/`pipeline`) | Tasks 1, 8 |
| Daily cron + workflow_dispatch + force_rebuild input | Task 3 |
| Concurrency group, contents+issues permissions | Task 3 |
| `detect-upstream.sh` with skip-if-exists logic | Task 2 |
| `sync-fork` job, force-push master + tag | Task 4 |
| `rebase-patches` job with `--force-with-lease` and conflict→issue | Task 5 |
| `verify` job — go build + go test at fork tag | Task 6 |
| Fork tag naming `v<UPSTREAM>-iconname` | Task 2 (script), Task 5 (apply) |
| One-time bootstrap of `set-icon-name` | Task 1 |
| Pipeline-branch README | Task 7 |
| Live dry-run validation | Task 8 |

No placeholders. No `generate-patches.sh`. No `cleanup-releases.sh`. No GH release step. Matches spec.
