# Systray Fork — Release-Tag Tracking Pipeline

Status: Approved
Date: 2026-05-21
Repo: `nnfewl/systray` (fork of `fyne-io/systray`)

## Problem

The fork carries a `SetIconName()` patch on top of `fyne.io/systray` (the current
working tree at `/home/sparkvix/Github/Personal-patch/src/systray-custom/` holds
the modified files). There is no automation to keep this patch aligned with new
upstream releases. Downstream consumers (a tailscale fork) need a stable, pinnable
revision per upstream release.

An earlier draft (`PLAN-systray-pipeline.md` in the custom-source tree) tracked
upstream `master` continuously. The new requirement is to **track only release
tags**, mirroring the approach used by the sibling `MEGAsync` fork.

## Goal

Automate, on a daily schedule:

1. Detect new upstream release tags (`v[0-9]+.[0-9]+.[0-9]+`).
2. Sync the tag + master into the fork.
3. Rebase the patch branch (`set-icon-name`) onto each new tag.
4. Publish the result as a fork tag `v<UPSTREAM>-iconname` for downstream pinning.
5. Verify the patched tree still builds and tests cleanly.

Conflicts surface as a GitHub issue. No GitHub Release. No build artifact.

## Repository layout

### Branches

| Branch | Purpose |
|---|---|
| `master` | Pure mirror of `fyne-io/systray` master. Fast-forwarded each pipeline run. Never edited by hand. |
| `set-icon-name` | Patch branch. Holds the `SetIconName()` commits on top of upstream. Rebased onto each new upstream release tag. |
| `pipeline` | Default branch. Contains only `.github/workflows/pipeline.yml`, `scripts/`, `docs/`, and this design. Never touches Go source. |

Three branches, three roles, no overlap. Editing one never disturbs another.

### Tags

- **Upstream tag pattern**: `^v[0-9]+\.[0-9]+\.[0-9]+$` (e.g. `v1.12.1`).
- **Fork tag**: `${UPSTREAM_TAG}-iconname` (e.g. `v1.12.1-iconname`), created at the
  HEAD of `set-icon-name` after a successful rebase.
- **Skip condition**: if `v<UPSTREAM>-iconname` already exists on the fork and
  `force_rebuild` is not set, the pipeline short-circuits.

### One-time bootstrap (manual, out of pipeline scope)

Before the first pipeline run, a human must:

1. Identify the latest upstream release tag at bootstrap time (currently `v1.12.1`).
2. Create `set-icon-name` off that tag.
3. Apply the source changes from `/home/sparkvix/Github/Personal-patch/src/systray-custom/`
   as one or more commits.
4. Push `set-icon-name` to the fork.
5. Create the `pipeline` branch with workflow + scripts (this design's implementation).
6. Set `pipeline` as the default branch on GitHub.

The pipeline does not perform bootstrap.

## Pipeline

### Triggers

- `schedule: cron: '0 6 * * *'` — daily at 06:00 UTC.
- `workflow_dispatch` with one input:
  - `force_rebuild` (boolean, default false) — re-runs build even if the fork
    tag already exists. Useful after fixing a rebase conflict manually.

### Concurrency

Single group `release-pipeline`, `cancel-in-progress: false`. Two concurrent
runs would race on force-pushes to `set-icon-name`.

### Permissions

`contents: write` (push tags, branches), `issues: write` (open conflict issues).

### Jobs

```
detect-upstream → sync-fork → rebase-patches → verify
                                    ↓ on conflict
                                open GH issue
                                  (exit 1)
```

#### `detect-upstream`

Runs `scripts/detect-upstream.sh`. The script:

1. Lists upstream tags via `gh api --paginate repos/fyne-io/systray/tags`.
2. Filters to `^v[0-9]+\.[0-9]+\.[0-9]+$` and picks the highest by `sort -V`.
3. Checks whether `${tag}-iconname` exists on the fork.
4. Sets `should-build=true` if (fork tag missing) OR (`FORCE_REBUILD=true`).

Outputs: `upstream-tag`, `upstream-version` (tag minus `v`), `fork-tag`, `should-build`, `today`.

Writes a `$GITHUB_STEP_SUMMARY` table for human inspection.

#### `sync-fork`

Gated on `should-build == 'true'`.

Adds upstream as a remote, fetches master + the specific tag, then:

```
git push origin refs/remotes/upstream/master:refs/heads/master --force
git push origin refs/tags/${UPSTREAM_TAG} --force
```

`--force` on master is safe because the fork's master is a pure mirror —
nothing else ever writes there. Forcing the tag covers the edge case of an
upstream re-tag.

#### `rebase-patches`

Gated on `should-build == 'true'`. Needs `sync-fork` (the tag must exist on origin).

```
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
      --body "Automated rebase of \`set-icon-name\` onto \`${UPSTREAM_TAG}\` failed.

Manual fix:

\`\`\`bash
git fetch origin
git checkout set-icon-name
git rebase ${UPSTREAM_TAG}
# resolve conflicts
git push origin set-icon-name --force-with-lease
\`\`\`

Re-run the pipeline:

\`\`\`bash
gh workflow run pipeline.yml --ref pipeline -f force_rebuild=true
\`\`\`" \
      --label "automation"
    exit 1
fi
```

On conflict the workflow exits 1, leaving the issue as the actionable signal.

`--force-with-lease` instead of `--force` to refuse pushes that would clobber
an out-of-band update to `set-icon-name` (e.g. someone pushed a fix mid-run).

#### `verify`

Gated on `should-build == 'true'`. Needs `rebase-patches`.

```
- uses: actions/checkout@v6
  with: { ref: ${{ needs.detect-upstream.outputs.fork-tag }} }
- uses: actions/setup-go@v5
  with: { go-version: 'stable' }
- run: go build ./...
- run: go test ./...
```

Pure validation. Failure here means the patched tree compiles or behaves
incorrectly post-rebase — the issue is the rebase or the patch, not the
pipeline. Failure does NOT roll back the tag (the tag is the artifact; if
it's broken, the next run after a fix overwrites it).

## Scripts

### `scripts/detect-upstream.sh`

Adapted from MEGAsync's version. Differences:
- Upstream repo is hardcoded to `fyne-io/systray`.
- Tag regex is `^v[0-9]+\.[0-9]+\.[0-9]+$` (no `_Linux` suffix).
- "Already built" check looks for the fork tag, not a release.

Exposed env: `FORCE_REBUILD`. Writes outputs to `$GITHUB_OUTPUT`.

### Removed from MEGAsync's set

- `generate-patches.sh` — not needed; patches live as commits on `set-icon-name`.
- `cleanup-releases.sh` — no releases.

Old `v*-iconname` tags accumulate; they are cheap and provide a reproducibility
audit trail. If they ever need pruning, that's a separate later script.

## Downstream consumption

The tailscale fork's `go.mod`:

```
replace fyne.io/systray => github.com/nnfewl/systray v1.12.1-iconname
```

Bumping is a one-line edit when a new upstream tag lands. The pipeline's
job is to make `v<NEW>-iconname` exist; the downstream bump is human-driven.

## Failure modes and responses

| Failure | Surface | Recovery |
|---|---|---|
| `detect-upstream` finds no matching tag | Workflow fails | Investigate; upstream regex may need to change. |
| Fork tag already exists, no force | `should-build=false`, all later jobs skipped | Normal no-op day. |
| `sync-fork` push rejected | Workflow fails | Check for branch protection on `master`; never expected. |
| `rebase-patches` conflict | Issue opened, workflow exits 1 | Manually rebase, force-push, re-run with `force_rebuild=true`. |
| `verify` build/test fails | Workflow fails after tag pushed | Fork tag is broken; fix patch on `set-icon-name`, re-run with `force_rebuild=true`. |

## Out of scope

- GitHub Releases or binary artifacts.
- Multi-platform CI (build/test runs only on `ubuntu-24.04`; the upstream lib's
  Windows and Darwin code paths are exercised by upstream and downstream
  consumers, not here).
- Automatic patch-file generation.
- Tag pruning.
- Auto-bumping the tailscale fork's `go.mod`.
