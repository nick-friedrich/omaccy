# Omaccy Hyperkey

Omaccy's bundled keyboard engine turns Caps Lock into Command+Control+Option.
It is a fork of [`feedthejim/hyperkey`](https://github.com/feedthejim/hyperkey)
at commit `532f2b38726fe0842cc947da023e3c7efec60b57` (MIT).

The upstream dual-path design is retained:

- `hidutil` maps Caps Lock to F18 and a `CGEventTap` handles built-in keyboards.
- IOKit HID seizure handles external keyboards that no longer reach event taps on
  macOS 26.

Hold **Hyper+U** to shrink or **Hyper+I** to grow the focused window. A tap
resizes once; holding repeats after 300 ms, about every 80 ms. Release either
key to stop. This works on built-in and seized external keyboards and triggers
the configured binding in AeroSpace’s current mode through its CLI. Customized
AeroSpace bindings still apply. Only one request runs at a time, so a slow server
cannot build up queued resize steps.
Changing modifiers stops repetition; configured app shortcuts take precedence.

Omaccy's fork deliberately omits Shift from the Hyper chord. Startup, updates,
and removal belong to Omaccy's installer rather than to this component.

Launch-or-focus application shortcuts are configured by bundle identifier in
`~/.config/omaccy/hyperkey.toml`. They launch closed apps and follow open
windows to their AeroSpace workspace. The defaults are:

```toml
[bindings]
b = "com.google.Chrome"
c = "com.openai.codex"
f = "com.apple.finder"
r = "com.apple.reminders"
t = "com.mitchellh.ghostty"
```

Build it with `swift build -c release --package-path apps/hyperkey` from the
repository root. Accessibility access is required when the installed app first
launches.

The full Omaccy installer also installs the custom SketchyBar configuration.
Its workspace buttons control AeroSpace, and its right-side status items show
tiling state, a Caffeinate control, battery, and the clock. The canonical
editable files live under `~/.omaccy/config/sketchybar` and are symlinked into
`~/.config/sketchybar` with any previous configuration backed up.

The compact Omaccy palette has six sections, **Apps**, **Agents**, **Install**, **Omaccy**, **Help**, and **System**:

- **Hyper+?** opens searchable shortcut help from your app bindings and AeroSpace
  configuration. Type `?` as usual for your keyboard layout (Shift+/ on US,
  Shift+ß on German).
- **Hyper+Space** opens the menu with keyboard-selectable Apps, Agents, Install, Omaccy, Help, and System collections. **Hyper+Shift+Space** still toggles
  floating windows in AeroSpace.
- **Hyper+A** launches your default agent directly; **Hyper+Shift+A** opens the
  Agents collection to browse or switch it.
- Type outside Install and Omaccy to search all apps, shortcuts, and system actions. Use ↑/↓ or Tab/Shift+Tab to
  select, and Return or a single click to browse a collection or launch/focus an
  app (including app shortcuts in Help). Escape clears
  search, then goes back to the menu, then closes it. Backspace on an empty search
  also goes back. Clicking outside or repeating the opening chord dismisses it.
- The Hyperkey status menu also offers **Omaccy Launcher**.

**Install** opens with all Homebrew-installed packages (including dependencies
and custom taps), with available updates first. Rows show installed versions and
Installed, Update available, or Pinned status. Type to search Homebrew’s official
formula and cask catalogs by name or
description. The catalog loads on first entry and is cached in memory for an hour;
reopen Install to retry a failed download. Exact names appear first, with up to
100 search matches shown; the installed list is not capped. Select a new package
to Install or an outdated package to Update, then confirm to run `brew install`
or `brew upgrade` in a dedicated Ghostty window,
where progress, password prompts, and errors remain visible. Homebrew must already
be installed in `/opt/homebrew` or `/usr/local`. Ghostty uses your terminal configuration and keeps the window open after the
command exits so you can read the result; press a key to close it. Existing Ghostty
windows are unaffected. Installed status refreshes whenever you enter Install; reopen it after
a Ghostty operation completes. Update availability uses Homebrew’s current local
metadata (`brew info --json=v2 --installed`); the launcher does not run `brew update`
automatically. Pinned packages remain pinned. Apps installed outside Homebrew are
not included in this inventory. Newly installed packages are user-requested packages, so Omaccy’s uninstaller leaves them
installed; remove them with `brew uninstall --formula NAME` or
`brew uninstall --cask NAME`. Search within Install stays scoped to Homebrew.

**Install → Upgrade all** manages bulk Homebrew upgrades.
It confirms the number of currently reported unpinned updates, then opens Ghostty
with `brew upgrade` for all eligible formulae and casks. Homebrew’s normal upgrade
rules apply, including pinned and self-updating apps; refreshed metadata may find
additional updates. Reopen Install after it finishes to refresh status. Individual package installs
and updates remain in Install.

**Omaccy → Update Omaccy** opens the checkout’s `scripts/update.sh` in Ghostty.
The script explains the changes and asks for confirmation, then rebuilds local
code, refreshes unchanged defaults, preserves customized configs, and restarts
Omaccy. It does not download newer repository code. Keep the checkout in place;
if it moves, run `scripts/update.sh` from its new location to restore the menu
entry’s path.

**Agents** lists Claude Code, Codex CLI, and opencode (terminal agents) plus the
Claude, ChatGPT, and T3 Code desktop apps. Return launches an installed agent;
⌘Return sets the selected agent as the `default_agent` that Hyper+A launches
directly. Terminal agents run inside [herdr](https://herdr.dev), a persistent
multiplexer for coding agents, kept alive by its own `brew services start herdr`
background daemon (started the same way this repo runs SketchyBar) so an agent
keeps running even after you close its window; each agent kind gets its own
labeled herdr workspace inside herdr's one shared session. Launching an agent
that's already running, or switching to a different already-provisioned one,
just focuses its herdr workspace and the AeroSpace workspace (`agent`) —
reusing an existing Ghostty window whenever one is already open there, rather
than spawning a duplicate. Provisioning a not-yet-running agent (creating its
workspace, starting it) happens headlessly the same way, before that same
reveal step decides whether a window is even needed. Desktop agents
launch like any other app binding. An agent that isn't installed yet is
installed via a confirmed `brew install` in Ghostty first, matching the Install
collection's pattern — herdr itself ships as a core Omaccy dependency,
installed alongside Ghostty, AeroSpace, and SketchyBar (uninstall only stops
and removes it when Omaccy installed it, since a pre-existing herdr may already
host unrelated agent sessions of your own).

**System** offers Sleep, Restart, and Shut Down. Sleep acts immediately; Restart
and Shut Down ask for confirmation with Cancel selected by default. macOS handles
quitting applications normally so they can prompt for unsaved work.

App discovery runs in the background and refreshes on opening. Apps in
`/Applications`, `~/Applications`, and the standard system Applications folders
are included. Help reads `~/.aerospace.toml` or
`~/.config/aerospace/aerospace.toml`; restart Hyperkey after changing app bindings
so the active shortcuts match the saved config. Hyper+Space is reserved for the
palette.

For UI development, run `.build/debug/omaccy-hyperkey --preview-menu` from this
package after building. This previews the palette without capturing keyboards
or changing Caps Lock mappings. Run `swift test --package-path apps/hyperkey`
from the repository root to check shortcut catalog coverage.
