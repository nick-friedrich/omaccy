# Repository map

| Path | Responsibility |
| --- | --- |
| `apps/hyperkey/` | Swift package, app metadata, keyboard engine, app launcher, and Apps, Install, Omaccy, Help, System & Settings palette |
| `config/` | Shipped defaults for Hyperkey, AeroSpace, Ghostty, SketchyBar, and the LaunchAgent |
| `scripts/install.sh` | Confirmation followed by the installation sequence |
| `scripts/update.sh` | Delegates to installation with the update explanation and one confirmation |
| `scripts/uninstall.sh` | Confirmation followed by service shutdown, restoration, and cleanup |
| `scripts/aerospace-control.sh` | Standalone start/stop/toggle command with IPC readiness handling |
| `scripts/theme.sh` | Standalone theme switcher; stores the choice in `~/.omaccy/theme` |
| `scripts/font.sh` | Standalone font switcher for Ghostty, SketchyBar, and the launcher |
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
- `~/.omaccy/theme` and `~/.omaccy/font` hold the appearance choices written by
  the theme and font switchers. SketchyBar resolves both at startup through
  `config/sketchybar/lib/palette.sh`; the launcher palette rereads them every
  time it opens. Fonts ship as the font-inter, font-jetbrains-mono, and
  font-lora Homebrew casks.
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

SketchyBar and the launcher palette share one appearance. Theme files in
`config/sketchybar/themes/` define an eight-color palette (BAR_BG, ITEM_BG,
BORDER, ACCENT, TEXT, MUTED, OK, DANGER) that sketchybarrc, its plugins, and
the Swift palette all consume; `config/sketchybar/lib/palette.sh` resolves the
active theme with Catppuccin Mocha fallbacks. `scripts/theme.sh` and
`scripts/font.sh` validate choices, write `~/.omaccy/theme` and `~/.omaccy/font`,
update Ghostty's font-family line, and restart SketchyBar only when its service
is running. The launcher's Settings collection mirrors those scripts through
`OmaccyAppearance` and rebuilds the open palette so changes preview immediately.
A font choice customizes the canonical Ghostty config, so updates preserve it.
SF Symbols stay on SF Pro because those glyphs only ship there.

`HomebrewCatalog.swift` loads the official formula/cask metadata asynchronously and
ranks package searches for the palette’s Install collection. The controller caches
the catalog in memory for an hour and confirms each install before handing it to
a dedicated Ghostty instance through NSWorkspace (no AppleScript automation).
The command runs in Bash with the Homebrew prefix on PATH; Ghostty keeps output
visible after exit and quits that instance when its last window closes.
Launcher-installed packages are user-managed, carry no Omaccy dependency
ownership markers, and are left installed by uninstall. Searching does not run brew
or mutate setup state.

`HomebrewInventory` reads installed formulae and casks using a bounded background
`brew info --json=v2 --installed` request with auto-update and analytics disabled.
Each entry to Install refreshes inventory independently of the remote catalog;
merging uses package kind plus full token so custom taps and formula/cask name
collisions remain distinct. An empty search lists all installed packages. Updates
use the local metadata’s outdated flag and confirmed `brew upgrade` commands;
pinned packages have no update action. Inventory failure disables package actions
until a successful refresh. Existing setup dependency ownership stays unchanged.

Install’s Upgrade all action uses a confirmed, fixed `brew upgrade` command in
Ghostty. Its count comes from the complete installed inventory, independent of
search results and their limit. Homebrew determines final eligibility, preserving
pins and its standard cask update rules. No bulk upgrade runs during validation.

The Omaccy collection offers Update Omaccy, opening `scripts/update.sh` from the
checkout in Ghostty. Installation records the checkout path inside the signed app
bundle at `Contents/Resources/omaccy-checkout.txt`; uninstall removes it with the
app. Debug builds resolve their source checkout. Missing/moved checkouts show a
recovery message instead of guessing another location. The updater receives the
path as a separate argument and clears the assume-yes override, retaining the
script’s single confirmation before setup changes. Ghostty survives the app’s
restart. This rebuilds local code; it does not fetch a newer Git revision.
Bulk Homebrew upgrades remain under Install alongside individual package actions.
