# Omaccy

A keyboard-centric, tiling macOS setup — an Omarchy-inspired "rice" that combines
best-of-breed tools with a thin glue layer of configs and one native app.

| Component | What it is |
| --- | --- |
| **Omaccy Hyperkey** | Custom Swift app: Caps Lock → Hyper (⌘⌃⌥), app launch shortcuts, and the Hyper+Space palette |
| **AeroSpace** | i3-style tree tiling with its own workspaces (no SIP changes) |
| **SketchyBar** | Menu-bar replacement, skinned to match the active theme |
| **Ghostty** | Default terminal, themed alongside the bar and the palette |
| **herdr** | Persistent multiplexer that keeps terminal coding agents alive |

Everything is installed from a checkout of this repository, with a clean
uninstall that restores the configs and macOS settings it displaced.

## Requirements

- macOS 13 or newer (Apple Silicon or Intel)
- Command Line Tools for Xcode (only for development; `swift` must be on PATH)
- SF Pro — installed automatically, without a password, for the menu bar icons
- Homebrew — installed automatically if missing

## Install

```bash
git clone https://github.com/nick-friedrich/omaccy.git && cd omaccy && bash scripts/install.sh
```

Keep the checkout: the installed configs are symlinked into it, and
`scripts/update.sh` and `scripts/uninstall.sh` run from there.

The script prints exactly what it will do and waits for a `y`/`yes`. Nothing on
the system changes before that confirmation. It then:

- installs any missing dependencies (Ghostty, AeroSpace, SketchyBar, herdr, and
  the Inter / JetBrains Mono / Lora fonts), recording which ones it installed
  so uninstall leaves pre-existing ones alone;
- downloads the signed, notarized **Omaccy Hyperkey** release, installs it to
  `~/Applications/Omaccy Hyperkey.app`, and registers its LaunchAgent;
- backs up any configs it displaces into a timestamped directory under
  `~/.omaccy/backups/`, then symlinks Omaccy's own;
- hides the native menu bar, disables the conflicting Mission Control arrow
  shortcuts, enables window grouping, and starts AeroSpace and SketchyBar.

macOS will ask to grant **Accessibility** access to Omaccy Hyperkey on first
launch; the keyboard engine does not work until you approve it.

`OMACCY_ASSUME_YES=1` bypasses every confirmation for unattended runs.

### Update

```bash
bash scripts/update.sh
```

One command for the whole update. It fast-forwards the checkout to the latest
commit on its remote branch, then reruns the installation sequence: refetches
the latest Hyperkey release, refreshes defaults that you have not edited, and
keeps the ones you have. Nothing happens before the single confirmation.

Only a fast-forward is ever performed, so your own commits are never rewritten.
When the checkout has uncommitted changes or commits the remote does not, or
the remote is unreachable, the code update is skipped with a note and setup
rebuilds from the revision you already have. `--no-pull` skips it deliberately.
Neither form upgrades already-installed Homebrew packages.

The app itself only ships on tagged releases, so a pulled checkout can be ahead
of the installed Omaccy Hyperkey. When it is, the update says so and names the
gap: those changes arrive with the next release, and nothing is broken in the
meantime.

### Uninstall

```bash
bash scripts/uninstall.sh
```

Stops the services, restores Caps Lock, the backed-up configs, and the changed
macOS settings, and asks separately before removing each dependency that Omaccy
installed. Packages you installed yourself — including anything installed
through the launcher's Install collection — are left in place.

## Using it

Hyper is **Caps Lock** (Command+Control+Option, deliberately without Shift).

| Shortcut | Action |
| --- | --- |
| `Hyper+Space` | Palette: Apps, Agents, Mail, Editors, Clipboard, Install, Help, System, Settings |
| `Hyper+?` | Searchable shortcut help, built from your live config |
| `Hyper+A` / `Hyper+Shift+A` | Launch your default coding agent / choose one |
| `Hyper+E` / `Hyper+Shift+E` | Launch your mail client / choose one |
| `Hyper+C` / `Hyper+Shift+C` | Launch your code editor / choose one |
| `Hyper+V` | Clipboard history: `↵` pastes, `⌘↵` copies, `⌘⌫` deletes |
| `Hyper+H/J/K/L` | Focus window left/down/up/right (`+Shift` moves it) |
| `Hyper+U` / `Hyper+I` | Shrink / grow the focused window (hold to repeat) |
| `Hyper+1…9` | Switch workspace (`+Shift` moves the window there) |
| `Hyper+T`, `+B`, `+F`, `+R` | Ghostty, Chrome, Finder, Reminders |

Each workspace has a **layout mode**, shown in the menu bar where the tiling
indicator used to just read "Tiling". Click it to pick a different one:

| Mode | What the workspace does |
| --- | --- |
| **Columns** | Every window a full-height column, side by side |
| **Rows** | Every window full width, stacked top to bottom |
| **Grid** | Windows squared off — four windows make a 2×2 |
| **Recursive** | New windows split beside the focused one, building a tree |
| **Accordion** | One window at a time, the rest collapsed to the edge |

Columns, Rows and Accordion hold themselves: AeroSpace adds a new window beside
the focused one, so in a flat workspace it simply becomes the next column or
row and nothing already on screen moves. Grid is rebuilt when a window opens,
since squaring off is the one shape that cannot maintain itself. Recursive
enforces nothing at all — pick it when you want the tree left alone.

The mode also makes `Hyper+U` / `Hyper+I` readable: resizing follows the
workspace's own direction, so in Columns it is always width and in Rows always
height. Modes are per workspace and survive restarts, in
`~/.omaccy/workspace-layout/`.

Click the date in the menu bar for a month calendar. Today is bracketed and its
week drawn in the theme's accent color; the rows underneath page a month back
or forward, clicking the month name returns to today, and **Open Calendar**
hands over to Calendar.app. The week starts on the day set under System
Settings → General → Language & Region, or your region's usual one.

Inside the palette, hold ⌘ to number the first nine rows and press ⌘1–9 to
run one directly. Escape steps back a page, landing on the row you came from,
and Escape again closes the palette.

Agents, Mail, and Editors each pick one app from a list and remember it:
Return launches the selected app, ⌘Return makes it the one that chord launches
directly, and an app you don't have yet offers to install itself through
Homebrew (or the Mac App Store, for Xcode). Mail includes
[Emzero](https://github.com/nick-friedrich/emzero), Apple Mail, Mimestream,
Thunderbird, Proton Mail, Spark, and Outlook; Editors includes Cursor, Zed, VS
Code, Xcode, Sublime Text, IntelliJ IDEA, and Nova.

App bindings live in `~/.config/omaccy/hyperkey.toml`; the tiling shortcuts are
plain AeroSpace bindings in `~/.config/aerospace/aerospace.toml`. Both are
symlinks into `~/.omaccy/config/`, which is where your edits belong — updates
preserve them. Binding `a`, `e`, or `c` there takes that letter back from its
collection, so a chord you have claimed yourself always wins.

Themes and fonts are shared by SketchyBar, the palette, and Ghostty:

```bash
bash scripts/theme.sh list && bash scripts/theme.sh set tokyo-night
bash scripts/font.sh set jetbrains-mono
```

Twelve palettes ship: Catppuccin Mocha, Catppuccin Latte, Dracula, Everforest,
GitHub Dark, Gruvbox Dark, Kanagawa, Nord, One Dark, Rosé Pine, Solarized Dark,
and Tokyo Night. Latte is the only light one. Each names the matching Ghostty
built-in theme, so the terminal follows along.

Both are also available under the palette's Settings, which previews changes
live.

VS Code and Cursor can follow the theme too, but only if you ask them to —
either from the switch at the top of Settings → Theme, or with:

```bash
bash scripts/theme.sh editors on
```

Their `settings.json` is your file, not Omaccy's, so nothing is written until
that opt-in — after which every theme switch rewrites `workbench.colorTheme`
in place (your comments and other settings survive) and both editors repaint
without a restart. Only Solarized Dark ships inside VS Code; the other eleven
palettes come from a marketplace extension, so the first switch to one installs
it with `code`/`cursor --install-extension`. The original `settings.json` is
copied to `~/.omaccy/backups/` before the first edit, and `editors off` stops
the whole thing.

If an editor has `"window.autoDetectColorScheme": true` — Cursor ships that on
— it ignores `workbench.colorTheme` outright and follows the OS appearance
instead, which looks exactly like the theme not applying. Omaccy turns that
setting off so the theme it writes is the one that shows, and says so when it
does.

macOS itself can follow the theme too, which is what makes the light palette
worth having:

```bash
bash scripts/theme.sh appearance on
```

Also a switch on Settings → Theme, and also opt-in: picking Catppuccin Latte
then puts macOS in Light and any dark palette puts it back. It needs a one-time
"control System Events" automation prompt, and it remembers the appearance it
found so uninstall can put that back. A theme file that does not declare
`APPEARANCE` — a custom palette, or one installed before this existed — leaves
macOS alone rather than guessing.

### Clipboard history

`Hyper+V` opens what you have copied, newest first. Return puts an entry back
on the clipboard and pastes it into whatever you were using, `⌘Return` only
copies it, and `⌘Delete` removes it. Typing searches the full text of every
entry, not just the line shown, so a value buried in something copied earlier
is still findable — but clipboard entries never appear in the palette's
global search, only on this page.

Entries
are held **in memory only** unless you turn on `clipboard_persist`, and the
history is cleared whenever Omaccy restarts.

That default is deliberate. Copies marked with the
[nspasteboard.org](http://nspasteboard.org) concealed convention are skipped,
as are copies from known password-manager apps — but a password copied from a
password manager's *browser extension* is written by the browser itself and
looks exactly like any other copy. Omaccy also declines to persist anything
copied without a ⌘C keystroke, which is how those extensions write, and drops
such entries from memory after 90 seconds. None of that is airtight, so
history stays off disk unless you ask otherwise.

Turn it on or off, choose whether it is kept on disk, and clear it under the
palette's Settings → Clipboard, or in `hyperkey.toml`:

```toml
clipboard_history = true
clipboard_persist = false
clipboard_limit = 200
```

## Development

Read [AGENTS.md](AGENTS.md) first, then [.ai/architecture.md](.ai/architecture.md)
for the repository map and [.ai/development.md](.ai/development.md) for the
lifecycle invariants that setup changes must preserve.

### Shell changes

Setup logic lives in `scripts/`, with reusable behavior in `scripts/lib/`
grouped by responsibility. Target the macOS system Bash (3.2). From the
repository root:

```bash
for script in scripts/*.sh scripts/lib/*.sh tests/*.sh; do bash -n "$script" || exit; done
bash tests/scripts-smoke.sh
git diff --check
```

The smoke checks run against temporary directories and only exercise
cancellation in the real entry points — they install nothing and touch no
services. A full install/uninstall changes your actual desktop, so treat it as a
deliberate manual integration check rather than a test.

### Hyperkey app changes

```bash
swift test --package-path apps/hyperkey
swift build -c release --package-path apps/hyperkey
```

To preview the palette UI without capturing keyboards or remapping Caps Lock:

```bash
swift build --package-path apps/hyperkey
apps/hyperkey/.build/debug/omaccy-hyperkey --preview-menu
```

`install.sh` never builds the Swift app — it downloads the published release. To
install the app from your working tree instead:

```bash
OMACCY_HYPERKEY_BUILD_LOCAL=1 bash scripts/install.sh
```

That build is signed with a Developer ID Application certificate when your
keychain holds one, and ad-hoc signed otherwise. Prefer Developer ID locally if
you can: its designated requirement binds to the bundle ID and team rather than
the binary's hash, so one Accessibility grant covers every rebuild *and* the
released app. Ad-hoc builds take a new code identity whenever the executable
changes and must be granted again each time. `OMACCY_SIGNING_IDENTITY` pins a
certificate by hash or name, or forces ad-hoc signing with `-`. See
[.ai/development.md](.ai/development.md) for the keychain prompt this raises the
first time.

Script-only changes need no rebuild.

## Releases

**A release is the Omaccy Hyperkey app only — not the whole project.**

The rest of Omaccy (the AeroSpace, SketchyBar, Ghostty, and Hyperkey configs,
and the setup scripts themselves) is distributed as this Git repository: you get
it by cloning, and `bash scripts/update.sh` both pulls it and reapplies it.
There is no release artifact, no Homebrew tap, and no
hosted one-line installer for that part.

The app is the exception because it is a native binary that needs Apple's
signing chain to run without warnings and to hold onto its Accessibility grant.
Pushing a `v*` tag runs [.github/workflows/release.yml](.github/workflows/release.yml),
which builds a universal (arm64 + x86_64) binary, stamps the version from the
tag, Developer ID-signs it, notarizes and staples it, verifies the result with
`stapler validate` and `spctl`, and publishes two assets:

```
omaccy-hyperkey-<version>.zip
omaccy-hyperkey-<version>.zip.sha256
```

```bash
git tag v0.3.0 && git push origin v0.3.0
```

`scripts/lib/hyperkey.sh` reads the latest release from the GitHub API, verifies
the archive against that checksum sidecar, and installs the bundle — so both the
asset filename pattern and the bare-hex checksum format are load-bearing. The
version needs no hand-bumping: CI stamps the tag into the bundle's `Info.plist`,
a local build stamps `git describe` instead, and the app reads whichever it was
given — so a build ahead of the last release says `0.4.0-3-gabc1234` rather than
repeating `0.4.0`.

Running the workflow manually (Actions → Release Hyperkey → Run workflow)
performs the identical build, signing, and notarization chain but skips
publishing, which is gated on a tag. Use it to verify credentials without
cutting a release.

[.ai/releasing.md](.ai/releasing.md) documents the required repository secrets,
certificate rotation, and troubleshooting.

## Repository layout

| Path | Contents |
| --- | --- |
| `apps/hyperkey/` | The Swift package: keyboard engine, launcher, and palette |
| `config/` | Shipped defaults for Hyperkey, AeroSpace, Ghostty, SketchyBar, LaunchAgent |
| `scripts/` | Install, update, uninstall entry points plus `lib/` and the theme, font, and AeroSpace helpers |
| `tests/` | Isolated shell lifecycle checks |
| `.ai/` | Architecture, development, and release documentation |
| `plan.md` | Historical decisions and future ideas — not a statement of what is implemented |

## Credits and license

Omaccy is MIT licensed; see [LICENSE](LICENSE).

The keyboard engine is a fork of
[`feedthejim/hyperkey`](https://github.com/feedthejim/hyperkey) (MIT); see
[apps/hyperkey/LICENSE](apps/hyperkey/LICENSE) and
[apps/hyperkey/UPSTREAM_NOTES.md](apps/hyperkey/UPSTREAM_NOTES.md). AeroSpace,
SketchyBar, Ghostty, and herdr are separate upstream projects installed through
Homebrew.
