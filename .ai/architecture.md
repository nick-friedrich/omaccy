# Repository map

| Path | Responsibility |
| --- | --- |
| `apps/hyperkey/` | Swift package, app metadata, keyboard engine, app launcher, and Apps, Agents, Mail, Editors, Install, Omaccy, Help, System & Settings palette |
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
| `scripts/lib/hyperkey.sh` | Fetches the signed, notarized release build by default (local Swift build under `OMACCY_HYPERKEY_BUILD_LOCAL=1`), plus launch |
| `tests/scripts-smoke.sh` | Isolated shell lifecycle checks |
| `.github/workflows/release.yml` | Builds, Developer ID-signs, notarizes, and publishes the hyperkey app to GitHub Releases on `v*` tags |
| `.ai/releasing.md` | Release pipeline, signing secrets, and certificate rotation |

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
- `~/.omaccy/hyperkey-signing-mode` records whether the installed app was
  ad-hoc or Developer ID signed, so Accessibility state is reset only when
  that identity actually changes.
- The app is installed at `~/Applications/Omaccy Hyperkey.app`; its LaunchAgent
  lives at `~/Library/LaunchAgents/com.omaccy.hyperkey.plist`.
- `~/.omaccy/hyperkey-release` records the installed release tag so reinstalls
  skip re-downloading an unchanged version; `~/.omaccy/hyperkey-checkout.txt`
  records the checkout path outside the signed app bundle, since writing into
  an already-notarized bundle's Resources after the fact would invalidate its
  signature.

## Current setup behavior

Run scripts from a complete local checkout using `bash scripts/install.sh`,
`bash scripts/update.sh`, or `bash scripts/uninstall.sh`. Paths are resolved from
the scripts, so the current working directory does not matter. A standalone
download of `install.sh` is insufficient: it requires the libraries and configs
from the checkout, though not the Swift sources — the hyperkey app itself comes
from the latest GitHub release by default. A hosted bootstrap installer (running
`install.sh` without a full checkout) and Homebrew distribution remain planning
topics; releases are published directly on GitHub instead of through a tap.

The hyperkey app ships as a Developer ID-signed, notarized build from
`.github/workflows/release.yml`, triggered by pushing a `v*` tag. `install.sh`
downloads the latest release's zip and its `.sha256` checksum from the GitHub
API, verifies the checksum, and replaces `$APP_DIR` with `ditto`; no local
build, codesign, or `tccutil` reset is needed since the signing identity is
stable across releases. Set `OMACCY_HYPERKEY_BUILD_LOCAL=1` to instead build
from the current checkout's Swift sources — the pre-existing ad-hoc-signed
path, needed when testing unreleased hyperkey changes, which still resets
Accessibility state when the built binary's hash changes.

Update reruns the installation sequence (refetching the latest hyperkey release
by default, or rebuilding from the current checkout under
`OMACCY_HYPERKEY_BUILD_LOCAL=1`) and refreshes pristine config defaults. It
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
active theme with Catppuccin Mocha fallbacks. Each theme file also names a
`GHOSTTY_THEME`, one of Ghostty's own bundled theme names (e.g. "Catppuccin
Mocha", "TokyoNight Night") chosen to match the palette, since Ghostty's theme
system is richer than the eight-color set and reimplementing it would drift.
`scripts/theme.sh` validates the choice, writes `~/.omaccy/theme`, rewrites
Ghostty's `theme` line to match, and restarts SketchyBar only when its
service is running; `scripts/font.sh` does the same for `~/.omaccy/font` but
leaves Ghostty alone — its `font-family` is fixed to JetBrains Mono in the
canonical config, since the UI font choices include proportional/serif faces
(Inter, Lora) that make no sense in a terminal. The launcher's Settings
collection mirrors those scripts through `OmaccyAppearance` and rebuilds the
open palette so changes preview immediately. Because Ghostty does not watch
its config file for changes on macOS, both the shell scripts and
`OmaccyAppearance.applyTheme` trigger a reload through Ghostty's bundled
scripting dictionary (`perform action "reload_config"`, from Ghostty.sdef) when
an instance is already running — this needs no Accessibility permission,
unlike System Events UI scripting. A theme choice customizes the canonical
Ghostty config, so updates preserve it. A custom theme file without a
`GHOSTTY_THEME` assignment leaves Ghostty's existing theme alone. SF Symbols
stay on SF Pro because those glyphs only ship there.

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

`AppCollections.swift` holds the picker collections that are plain app choices:
Mail (Hyper+E) and Editors (Hyper+C). Each is a fixed list of interchangeable
apps with one default recorded in `hyperkey.toml` (`default_mail`,
`default_editor`); ⌘Return sets it, Return launches the selected app through
the same `focusOrLaunch` path as a configured binding. Agents keep their own
type because terminal agents run inside herdr rather than launching as apps.

A choice names the bundle it installs as (`Cursor.app`) and reads the real
bundle identifier off that bundle at use time, rather than carrying a hardcoded
identifier for an app we do not build: a stale identifier would break launching
and installed-detection silently, and only the identifiers of apps found in
`/Applications`, `/System/Applications`, or `~/Applications` are ever needed.
An uninstalled choice offers its own install route — a confirmed `brew install`
in Ghostty, matching the Install collection, or the Mac App Store for Xcode,
which Homebrew does not carry — and the result stays user-managed, so uninstall
leaves it alone.

Each collection advertises its chord: on its Home row, in its own page header
(`✦ ⇧ E`), and beside the chosen default. All three are suppressed for a letter
claimed by `[bindings]`, so the palette never shows a shortcut that does not
work. `MenuShortcut` renders Hyper as ✦ and Shift as ⇧ for display only —
entries keep their written chords so search still matches "hyper" — and the
chord sits in its own muted label so a browsable row keeps its accented
chevron. `--preview-menu` takes an optional page name for
developing these pages, which cannot be reached by chord in a preview.

The picker chords (Hyper+A, Hyper+E, Hyper+C) yield to an explicit `[bindings]`
entry on the same letter, unlike Hyper+Space and Hyper+?, which are
unconditional. The shipped config therefore no longer binds `c`, but a user who
binds it keeps their app. `Configuration` ignores commented-out lines, which its
`#`-splitting previously treated as live settings whenever the comment contained
a `key = value`.

The Agents collection (`AgentCatalog.swift`) lists three terminal agents (Claude
Code, Codex CLI, opencode) and three desktop apps (Claude, ChatGPT, T3 Code).
Hyper+A launches the agent named by `default_agent` in `hyperkey.toml` directly,
falling back to opening the Agents collection when unset; Hyper+Shift+A always
opens it. Selecting an entry sets `default_agent` with ⌘Return; Return launches
it. Desktop agents launch by bundle ID like ordinary app bindings and install
through the same confirmed-`brew install`-in-Ghostty path as the Install
collection.

Terminal agents run inside herdr, a persistent multiplexer for coding agents,
using its one shared *default* session rather than a session per agent kind: a
session herdr itself doesn't own the lifecycle of would need its own service
supervision to survive a closed terminal, whereas the default session is kept
alive by `brew services start herdr` — a real launchd daemon, installed and
started the same way this repo already runs SketchyBar. Each agent kind gets
its own labeled herdr *workspace* inside that one session.

When herdr and the agent binary are already installed, `activateAgent` does
all of the herdr socket-API work headlessly, off the main thread, before
deciding whether a terminal is even needed: `HerdrBridge.runningWorkspaceID`
asks herdr (`agent get <binary>`) whether the agent is already alive; if not,
`HerdrBridge.provisionWorkspace` creates its labeled workspace and starts it
there — neither step touches a pty. Either way the result is a workspace ID to
focus, then `revealAgentWorkspace` switches to the AeroSpace `agent` workspace
and opens a Ghostty window running only `exec herdr` — but only when
`HotkeyBindings.ghosttyWindowExists` finds none already there. So reattaching
to a running agent, and switching to a different already-provisioned one, are
both instant and never spawn a duplicate window; a Ghostty window already open
for one agent is reused (via herdr's own workspace focus) when launching
another. Only when something needs installing does `confirmAndInstallTerminalAgent`
take the slower, visible path: after confirming, `launchTerminalAgent` runs an
idempotent script in a dedicated new Ghostty window (install progress and any
password prompt should actually be seen) that installs what's missing, starts
herdr's service, provisions the workspace, and `exec herdr`s to attach.

herdr is a core Omaccy dependency (`ensure_formula herdr`), installed
alongside Ghostty, AeroSpace, and SketchyBar; uninstall only stops and removes
it when Omaccy itself installed it, since a pre-existing herdr may be hosting
the user's own unrelated agent sessions in that same default session.

The Omaccy collection offers Update Omaccy, opening `scripts/update.sh` from the
checkout in Ghostty. Installation records the checkout path at
`~/.omaccy/hyperkey-checkout.txt`, outside the signed app bundle so the
downloaded, notarized release build never needs re-signing; uninstall removes
it alongside the app. Debug builds resolve their source checkout. Missing/moved
checkouts show a recovery message instead of guessing another location. The
updater receives the path as a separate argument and clears the assume-yes
override, retaining the script's single confirmation before setup changes.
Ghostty survives the app's restart. This reruns the installation sequence; it
does not fetch a newer Git revision.
Bulk Homebrew upgrades remain under Install alongside individual package actions.
