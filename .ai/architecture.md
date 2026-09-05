# Repository map

| Path | Responsibility |
| --- | --- |
| `apps/hyperkey/` | Swift package, app metadata, keyboard engine, app launcher, and Apps, Help & System palette |
| `config/` | Shipped defaults for Hyperkey, AeroSpace, Ghostty, SketchyBar, and the LaunchAgent |
| `scripts/install.sh` | Confirmation followed by the installation sequence |
| `scripts/update.sh` | Delegates to installation with the update explanation and one confirmation |
| `scripts/uninstall.sh` | Confirmation followed by service shutdown, restoration, and cleanup |
| `scripts/aerospace-control.sh` | Standalone start/stop/toggle command with IPC readiness handling |
| `scripts/lib/paths.sh` | Repository and installed-state paths; no directory creation |
| `scripts/lib/prompts.sh` | Yes/No handling and descriptions of install, update, and uninstall |
| `scripts/lib/dependencies.sh` | Homebrew setup, ownership markers, and optional dependency removal |
| `scripts/lib/config.sh` | Config copying, hash stamps, symlinks, backup/restore, and legacy migration |
| `scripts/lib/macos.sh` | Menu-bar and Mission Control settings with paired restoration functions |
| `scripts/lib/hyperkey.sh` | Swift build, app signing, build-hash tracking, and launch |
| `tests/scripts-smoke.sh` | Isolated shell lifecycle checks |

## Installed state

- `~/.omaccy/config/` holds canonical editable configs. Tool-specific paths link
  to those files. `~/.omaccy/backups/` holds displaced originals.
- `~/.omaccy/sha256/` records shipped content so updates can refresh unchanged
  defaults while retaining customized files.
- Dependency markers distinguish packages installed by Omaccy from packages
  already present. `*.original` files preserve macOS preference values.
- The app is installed at `~/Applications/Omaccy Hyperkey.app`; its LaunchAgent
  lives at `~/Library/LaunchAgents/com.omaccy.hyperkey.plist`.

## Current setup behavior

Run scripts from a complete local checkout using `bash scripts/install.sh`,
`bash scripts/update.sh`, or `bash scripts/uninstall.sh`. Paths are resolved from
the scripts, so the current working directory does not matter. A standalone
download of `install.sh` is insufficient: it requires the libraries, configs,
and Swift sources. A hosted bootstrap installer and Homebrew distribution remain
planning topics.

Update rebuilds from the current checkout and refreshes pristine defaults. It
does not fetch Git changes or upgrade already installed Homebrew packages.

All three operations explain their effects and require Y/Yes (case-insensitive).
Empty input, EOF, and other answers cancel. The existing explicit automation
override, `OMACCY_ASSUME_YES=1`, bypasses every confirmation, including dependency
removal prompts. The summary and automatic-confirmation notice still print.

The keyboard engine uses Command+Control+Option for Hyper, without Shift.
`ResizeKeyRepeat.swift` supplies timed Hyper+U/I binding requests for both input paths;
key/Hyper release, modifier changes, tap disablement, and keyboard removal stop
repetition. A background CLI request resolves the current AeroSpace mode and
uses `trigger-binding`, with at most one request in flight to avoid a backlog.
AeroSpace remains responsible for the shortcut commands.
AeroSpace uses its own workspaces. Mission Control grouping is enabled as a
workaround for tiny previews; its original preference is restored on uninstall.

Starting AeroSpace re-enables an already running but disabled server before
checking workspace readiness. This handles reinstall after uninstall without
blocking the subsequent SketchyBar service startup. SketchyBar is started through
Homebrew services and registered to start at login.

Setup prompts display the timestamped config backup directory and explain
restoration. These backups preserve displaced originals; they are not a history
of edits to Omaccy's canonical configs. Updates preserve those edits, but uninstall
removes the canonical configs, as stated in its confirmation prompt.
