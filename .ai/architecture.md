# Repository map

| Path | Responsibility |
| --- | --- |
| `apps/hyperkey/` | Swift package, app metadata, keyboard engine, app launcher, clipboard history, and Apps, Agents, Mail, Editors, Install, Help, System & Settings palette |
| `config/` | Shipped defaults for Hyperkey, AeroSpace, Ghostty, SketchyBar, and the LaunchAgent |
| `scripts/install.sh` | Confirmation followed by the installation sequence |
| `scripts/update.sh` | One confirmation, then the checkout fast-forward, then the installation sequence |
| `scripts/uninstall.sh` | Confirmation followed by service shutdown, restoration, and cleanup |
| `scripts/aerospace-control.sh` | Standalone start/stop/toggle command with IPC readiness handling |
| `scripts/theme.sh` | Standalone theme switcher; stores the choice in `~/.omaccy/theme` |
| `scripts/font.sh` | Standalone font switcher for Ghostty, SketchyBar, and the launcher |
| `scripts/lib/paths.sh` | Repository and installed-state paths; no directory creation |
| `scripts/lib/prompts.sh` | Yes/No handling and descriptions of install, update, and uninstall |
| `scripts/lib/git.sh` | Best-effort fast-forward of the checkout setup runs from |
| `scripts/lib/fonts.sh` | Sudo-free SF Pro install, ownership, and removal |
| `scripts/lib/dependencies.sh` | Homebrew setup, ownership markers, login-service registration, and optional dependency removal |
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
- `~/.omaccy/clipboard/history.json` holds clipboard history, written at mode
  0600 and only while `clipboard_persist` is on; the default is memory-only, so
  the directory usually does not exist. `ClipboardHistory.swift` documents why:
  a password copied from a password manager's browser extension carries no
  concealed marker and is attributed to the browser, so it cannot be filtered
  out with certainty. Entries copied without a ⌘C keystroke (how extensions
  write) are never persisted and expire from memory after 90 seconds. The
  pasteboard read runs off the main run loop, since lazily-provided items make
  it an IPC round-trip to the owning app and the CGEventTap shares that loop.
  Hyper+V opens the history page, which yields to a `[bindings]` entry on `v`
  like the other reserved chords. Pasting writes the entry back, claims the
  resulting change count so the write is not read back as a new copy, and posts
  ⌘V tagged with `Constants.injectedEventMarker` so the app's own tap passes it
  through undecorated.
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

Update fast-forwards the checkout, then reruns the installation sequence
(refetching the latest hyperkey release by default, or rebuilding from the
current checkout under `OMACCY_HYPERKEY_BUILD_LOCAL=1`) and refreshes pristine
config defaults. It does not upgrade already installed Homebrew packages.

The fast-forward is a best-effort step in front of that sequence, never a gate
on it. `scripts/lib/git.sh` refuses in every case where pulling could lose or
rewrite work — a missing git, a non-checkout, a detached HEAD, a branch with no
upstream, uncommitted changes, an unreachable remote, or commits the remote
does not have — and each refusal prints its reason, says setup continues from
the present revision, and returns success. Only `merge --ff-only` is ever run.
`--no-pull` skips the step deliberately, which is also how the smoke checks
exercise the rebuild without a network.

Configs and scripts ship continuously from the repository while the app ships
only on `v*` tags, so a pulled checkout can hold app changes the installed
release lacks. Around a quarter of this project's commits touch both `config/`
and `apps/hyperkey/`, so a config can land referencing a feature the running
binary does not have — which reads as a broken setting rather than a wait.
`warn_hyperkey_checkout_skew` closes the setup sequence by comparing the tag in
`~/.omaccy/hyperkey-release` against the checkout's `apps/hyperkey/` history and
naming the gap. It stays silent whenever it cannot speak accurately: no recorded
release (a local build removes that stamp, so there is genuinely nothing to
compare), a tag absent from the checkout, or an uncountable history. The
warning is a net for the window between a config landing on `main` and the
release that carries its app half; tagging when a commit touches both trees is
what keeps that window short.

The update prompt covers both the code update and the setup sequence it feeds,
so `update.sh` owns the single confirmation and exports `OMACCY_SETUP_CONFIRMED`
for the install run it hands off to; `confirm_setup` returns early on that
rather than asking twice. Ordering is load-bearing: nothing is fetched or
merged until after the confirmation, so declining still leaves the checkout
untouched. `update.sh` keeps its work in a `main` function that ends in `exec`,
because Bash reads a script as it runs it and a pull rewriting the file mid-run
would otherwise resume at a stale byte offset. The exec also means install.sh
and its libraries are read fresh, at the newly pulled revision.

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

A daemon already running outside launchd holds whatever socket it binds, so
`brew services start` fails its bootstrap (exit 5, and `brew services list`
then reports "error") even though the program itself is working. herdr does
this whenever it is already hosting agent sessions. `ensure_login_service`
reports that case as the non-problem it is — only login-time auto-start is
affected — and surfaces brew's own output only when the daemon really is not
running.

The Hyperkey LaunchAgent has the mirror-image problem. An update that finds the
installed release tag unchanged returns early without unloading the agent, so a
bare `launchctl bootstrap` met a label that was already loaded and failed with
"Bootstrap failed: 5: Input/output error" — under errexit that aborted the rest
of setup, leaving AeroSpace, SketchyBar, and herdr unstarted. `start_hyperkey`
is therefore a restart: it boots the agent out, waits for launchd to finish the
teardown rather than racing the next bootstrap, then bootstraps. That is also
what puts a newly installed binary into service, since bootstrapping over a
live agent would leave the previous process running. A bootstrap that still
fails warns with launchd's own output and returns success, so the steps after
it survive. All launchd calls go through the `hyperkey_launchctl` seam so the
smoke checks can exercise this without a real domain.

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

macOS does not ship SF Pro as an installable family, so a machine without it
drew blank gaps where the clock, battery, caffeinate, and tiling icons belong —
the icons are private-use SF Symbols codepoints that exist in no other font.
Homebrew's `font-sf-pro` cask installs a system-domain `.pkg` and would put a
password prompt inside an installer that otherwise never needs one, so
`scripts/lib/fonts.sh` expands Apple's disk image and copies one file,
`SF-Pro.ttf`, into `~/Library/Fonts` as the user — the same directory the Inter,
JetBrains Mono, and Lora casks already write to. That file alone is the variable
font whose family is literally "SF Pro" with a Semibold named instance, which is
what the SketchyBar config asks for; the 45 static Display/Text/Rounded faces
beside it are separate families and would only clutter the font book. SF Pro
found in any domain is recorded as pre-existing and left alone by uninstall.

The install is never fatal, because `config/sketchybar/lib/icons.sh` gives every
SF Symbol a plain-Unicode twin and picks the set at startup by looking for
`SF-Pro.ttf`. A declined, failed, or offline font install therefore costs the
nicer glyphs and nothing else. Both `sketchybarrc` and `plugins/battery.sh`
source that file rather than hardcoding glyphs, so the two sets cannot drift.

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
Ghostty survives the app's restart. Because `update.sh` now pulls first, this
menu action is a complete update rather than a rebuild of the present revision.
Bulk Homebrew upgrades remain under Install alongside individual package actions.
