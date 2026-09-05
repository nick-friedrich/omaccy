# Omaccy — macOS Omakub-inspired setup

This document includes historical decisions and planned features. For the current
repository structure and setup behavior, see [.ai/architecture.md](.ai/architecture.md)
and [.ai/development.md](.ai/development.md).

A zero-drama, Omakub-inspired "rice" for macOS. Keyboard-centric, tiling, with a clean install/uninstall story.

## Architecture

We use best-of-breed tools rather than building everything ourselves. Our own work is the thin "glue" layer: configs and one SwiftUI app.

| Component | Tool | License | Role |
|---|---|---|---|
| Key remap | **Our own Swift app (hyperkey daemon)** | ours (MIT) | Caps Lock → Hyper (⌘⌃⌥, no Shift) via CGEventTap |
| Tiling | **AeroSpace** | MIT | i3-style tree tiling + its own workspaces |
| Status bar | **SketchyBar** | MIT | Custom menubar-replacement bar, our config/skin |
| Super menu | **Our SwiftUI app** | ours | Hyper+Space palette: search apps + quick actions |
| Hotkeys | Our Swift app | — | Hyper+letter launch; Hyper+Space palette |
| Terminal | **Ghostty** | MIT | Default terminal, launched with Hyper+T |
| Install | curl \| bash script | ours | One-line setup, Homebrew deps, configs, app |
| Distribution | Homebrew tap | ours | `brew install omaccy` |

## Feature decisions

### 1. Caps Lock rebinding — **Karabiner DROPPED, building our own**

**Why we dropped Karabiner-Elements** (macOS 26 / Tahoe):
- Caps Lock never became Hyper despite a verified-correct complex-modification rule, a clean single core-service, and the proven carrier-key pattern.
- Its GUI rewrites `~/.config/karabiner/karabiner.json` in place on every visit (ignoring our symlink), forcing the "choose keyboard type" dialog and breaking our config symlink on repeat.
- Karabiner's own DriverKit virtual-keyboard broke on macOS 26.4 beta (pqrs-org/Karabiner-Elements#4402) — the underlying driver is fragile on Tahoe.

**New approach — fork `feedthejim/hyperkey` (MIT) into Omaccy's hyperkey engine:**
- `hidutil` (built-in, via a LaunchAgent) maps Caps Lock → F18 at the HID level first: kills the caps-toggle + caps-lock delay.
- Fork `feedthejim/hyperkey` (MIT, github.com/feedthejim/hyperkey) — a menubar app that uses `CGEventTap` + IOKit HID seizure to turn F18 into a real **Hyper** modifier. It was written specifically because Karabiner broke on macOS 26, and it handles the macOS 26+ external-keyboard gap via IOKit HID seizure.
- **Our change:** strip Shift from `Constants.hyperFlags` → **⌘⌃⌥ (no Shift)**.
- Ships as part of Omaccy (MIT); needs the one-time Accessibility grant (same as every key-remap/daemon option).
- Rides no Karabiner/DK dext, so no `karabiner.json`, no rewrite loop, no dialogs as the Kara/daemon.
- Alternatives considered and rejected: KMonad (MIT) rides the same Karabiner DriverKit dext that broke on macOS 26 and needs root daemon + GUI driver approval. Hammerspoon (MIT) works but is a separate runtime just for one key.

### 2. App launching
- **Hyper + letter** → launch or focus a bound app across workspaces
  (Hyper+B → Chrome, Hyper+C → ChatGPT, Hyper+F → Finder,
  Hyper+R → Reminders, Hyper+T → Ghostty).
- **Hyper + Space** → open the super menu palette for everything else.
- Bindings are user-editable in our TOML config.
- Ghostty is installed through Homebrew when missing; an existing user installation is preserved on uninstall.

### 3. Status bar
- SketchyBar with our custom config/skin.
- Shows workspace name, tiling on/off, a Caffeinate control, battery, and the clock.
- Ships as a config SKIN we distribute; user's existing SketchyBar config is preserved (see Config safety).

### 4. Tiling
- AeroSpace with the **i3 tree tiling** paradigm (default).
- Uses **AeroSpace's own workspace emulation**, not native macOS Spaces.
- No SIP disabling required.

### 5. Super menu (our Swift app)
- **SwiftUI** app.
- Trigger: **Hyper + Space** — a Raycast-style palette appears.
- Content: search bar over installed apps + a set of quick actions.
- Quick actions (initial set): toggle tiling, toggle Omaccy (everything), lock screen, sleep, restart, controls for SketchyBar/AeroSpace state.

### 6. Toggle controls
- **Toggle Tiling** → stops/starts AeroSpace only.
- **Toggle Omaccy** → stops everything: AeroSpace, SketchyBar, our app (incl. the hyperkey daemon → Caps Lock returns to normal).
- Both reachable from the super menu quick actions.

### 7. Install / uninstall
- **One-line installer**: `curl -fsSL https://.../install.sh | bash`.
- Steps:
  1. Ensure Homebrew.
  2. Install deps (Ghostty, AeroSpace, SketchyBar) and build/install the bundled hyperkey daemon.
  3. Back up any existing configs (see Config safety).
  4. Our configs live in a canonical location (e.g. `~/.omaccy/config/` shipped/versioned), and are **symlinked** into each tool's expected path (AeroSpace `~/.config/aerospace/aerospace.toml`, SketchyBar config, our hyperkey daemon config, etc.). Users edit the real files in `~/.omaccy/config/`; symlinks point at them.
  5. Install our Swift app (Homebrew tap).
  6. Grant required permissions (Accessibility etc.) and prompt the user to finish.
- **Uninstall**: reverses every step — removes our symlinks, restores user's original configs (moved back from backup), removes our app/configs and any Omaccy-only deps, and re-enables normal Caps Lock (remove the hidutil mapping / stop the daemon).

### 8. Config safety
- Never override an existing user config for AeroSpace / SketchyBar / etc.
- Conflicting-config handling via symlinks:
  - If the target path already exists and is **not** already a symlink to ours: move it to a **timestamped backup**, then create our symlink.
  - If it's already our symlink: leave it alone.
  - On uninstall: remove only **our** symlinks and restore the backups.
- Our own config (app bindings, settings) must never clobber a user's existing AeroSpace / SketchyBar configs.

## Implementation roadmap

- [x] **Hyper key implementation decided**: fork `feedthejim/hyperkey` (MIT) → strip Shift — see §1.
- [x] **Hyperkey engine vendored:** forked `feedthejim/hyperkey` at `532f2b3`, removed Shift from `Constants.hyperFlags`, added symlinked TOML config and LaunchAgent startup, and retained the Accessibility onboarding prompt.
- [x] **Global app bindings:** Hyper chords can launch or focus bundle identifiers
  across workspaces from `hyperkey.toml`; defaults map Hyper+B to Chrome,
  Hyper+C to ChatGPT, Hyper+F to Finder, Hyper+R to Reminders, and Hyper+T to Ghostty.
- [x] **Ghostty config wired:** the active config is deployed through `~/.omaccy/config`, symlinked into Ghostty's Application Support directory, and restored safely on uninstall.
- [x] **AeroSpace tiling wired:** an initial Hyper-driven i3-style config is deployed through `~/.omaccy/config`, AeroSpace is installed only when missing, its live config uses the backup-safe symlink lifecycle, and `scripts/aerospace-control.sh` provides start/stop/toggle commands.
- [x] **Custom menu bar wired:** SketchyBar is managed with `brew services`, its backup-safe config shows AeroSpace workspaces, the front app, tiling availability, Caffeinate state, battery, and time, and workspace changes update immediately.
- [ ] How our app registers the **Hyper+Space** global hotkey — `CGEvent.tapCreate` vs. Carbon `RegisterEventHotKey`.
- [ ] Config sync across machines — user-managed dotfiles vs. our own sync mechanism.

## Resolved decisions

- Swift app framework: **SwiftUI**
- Config format: **TOML** (matches AeroSpace)
- Distribution: **Homebrew tap**
- App-launch model: **Hotkeys + palette** (both)
- Super-menu trigger: **Hyper + Space**
- Super-menu contents: **Apps + quick actions**
- Toggle scope: **Two toggles** (tiling only, or everything)
- Install method: **One-line curl script**
- Conflicting-config handling: **Symlink into place, backup any existing real files → restore on uninstall**
- **Hyper key: Karabiner-Elements dropped → own CGEventTap daemon (failed on macOS 26)**
