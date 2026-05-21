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
