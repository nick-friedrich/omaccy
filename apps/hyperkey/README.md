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

The compact Omaccy palette has three sections, **Apps**, **Help**, and **System**:

- **Hyper+?** opens searchable shortcut help from your app bindings and AeroSpace
  configuration. Type `?` as usual for your keyboard layout (Shift+/ on US,
  Shift+ß on German).
- **Hyper+Space** opens the menu with keyboard-selectable Apps, Help, and System collections. **Hyper+Shift+Space** still toggles
  floating windows in AeroSpace.
- Type anywhere to search all apps, shortcuts, and system actions. Use ↑/↓ or Tab/Shift+Tab to
  select, and Return or a single click to browse a collection or launch/focus an
  app (including app shortcuts in Help). Escape clears
  search, then goes back to the menu, then closes it. Backspace on an empty search
  also goes back. Clicking outside or repeating the opening chord dismisses it.
- The Hyperkey status menu also offers **Omaccy — Apps, Help & System**.

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
