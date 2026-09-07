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
checkout in Ghostty. Installation records the checkout path inside the signed app
bundle at `Contents/Resources/omaccy-checkout.txt`; uninstall removes it with the
app. Debug builds resolve their source checkout. Missing/moved checkouts show a
recovery message instead of guessing another location. The updater receives the
path as a separate argument and clears the assume-yes override, retaining the
script’s single confirmation before setup changes. Ghostty survives the app’s
restart. This rebuilds local code; it does not fetch a newer Git revision.
Bulk Homebrew upgrades remain under Install alongside individual package actions.
