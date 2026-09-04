# Omaccy Hyperkey

Omaccy's bundled keyboard engine turns Caps Lock into Command+Control+Option.
It is a fork of [`feedthejim/hyperkey`](https://github.com/feedthejim/hyperkey)
at commit `532f2b38726fe0842cc947da023e3c7efec60b57` (MIT).

The upstream dual-path design is retained:

- `hidutil` maps Caps Lock to F18 and a `CGEventTap` handles built-in keyboards.
- IOKit HID seizure handles external keyboards that no longer reach event taps on
  macOS 26.

Omaccy's fork deliberately omits Shift from the Hyper chord. Startup, updates,
and removal belong to Omaccy's installer rather than to this component.

Application shortcuts are configured by bundle identifier in
`~/.config/omaccy/hyperkey.toml`. The default maps Hyper+T to Ghostty:

```toml
[bindings]
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
