# Omaccy — macOS Omakub-inspired setup

A zero-drama, Omakub-inspired "rice" for macOS. Keyboard-centric, tiling, with a clean install/uninstall story.

## Architecture

We use best-of-breed tools rather than building everything ourselves. Our own work is the thin "glue" layer: configs and one SwiftUI app.

| Component | Tool | License | Role |
|---|---|---|---|
| Key remap | **Karabiner-Elements** | Unlicense | Caps Lock → Hyper (⌘⌃⌥, no Shift) |
| Tiling | **AeroSpace** | MIT | i3-style tree tiling + its own workspaces |
| Status bar | **SketchyBar** | MIT | Custom menubar-replacement bar, our config/skin |
| Super menu | **Our SwiftUI app** | ours | Hyper+Space palette: search apps + quick actions |
| Hotkeys | Karabiner + our app | — | Hyper+letter launch; Hyper+Space palette |
| Install | curl \| bash script | ours | One-line setup, Homebrew deps, configs, app |
| Distribution | Homebrew tap | ours | `brew install omaccy` |

## Feature decisions

### 1. Caps Lock rebinding
- Caps Lock → **Hyper key = ⌘ + ⌃ + ⌥** (no Shift), so it never conflicts with normal shortcuts.
- Implemented as a Karabiner-Elements complex modification in our config.
- Karabiner-Elements is **Unlicense** (public domain): free to bundle, modify, and distribute. Dropping it later is not a real risk.

### 2. App launching
- **Hyper + letter** → launch a bound app directly (e.g. Hyper+T → Terminal, Hyper+F → Finder).
- **Hyper + Space** → open the super menu palette for everything else.
- Bindings are user-editable in our TOML config.

### 3. Status bar
- SketchyBar with our custom config/skin.
- Shows workspace name, tiling on/off, and system info (battery, wifi, clock, etc.).
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
- **Toggle Omaccy** → stops everything: AeroSpace, Karabiner remap, SketchyBar, our app.
- Both reachable from the super menu quick actions.

### 7. Install / uninstall
- **One-line installer**: `curl -fsSL https://.../install.sh | bash`.
- Steps:
  1. Ensure Homebrew.
  2. Install deps (Karabiner-Elements, AeroSpace, SketchyBar).
  3. Back up any existing configs (see Config safety).
  4. Our configs live in a canonical location (e.g. `~/.omaccy/config/` shipped/versioned), and are **symlinked** into each tool's expected path (Karabiner `~/.config/karabiner/karabiner.json`, AeroSpace `~/.config/aerospace/aerospace.toml`, SketchyBar config, etc.). Users edit the real files in `~/.omaccy/config/`; symlinks point at them.
  5. Install our Swift app (Homebrew tap).
  6. Grant required permissions (Accessibility etc.) and prompt the user to finish.
- **Uninstall**: reverses every step — removes our symlinks, restores user's original configs (moved back from backup), removes our app/configs and any Omaccy-only deps, and re-enables normal Caps Lock.

### 8. Config safety
- Never override an existing user config for Karabiner / AeroSpace / SketchyBar / etc.
- Conflicting-config handling via symlinks:
  - If the target path already exists and is **not** already a symlink to ours: move it to a **timestamped backup**, then create our symlink.
  - If it's already our symlink: leave it alone.
  - On uninstall: remove only **our** symlinks and restore the backups.
- Our own config (app bindings, settings) must never clobber a user's existing Karabiner / AeroSpace / SketchyBar configs.

## Implementation notes (still to settle)

- [ ] How our app toggles **Karabiner** — `karabiner_cli` profile switch vs. `launchctl` around its services.
- [ ] How our app toggles **AeroSpace** — `aerospace` CLI (kill/relaunch process).
- [ ] How our app toggles **SketchyBar** — `brew services start/stop sketchybar` vs. `killall`/relaunch.
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