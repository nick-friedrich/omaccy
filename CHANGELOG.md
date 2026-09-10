# Changelog

Notable changes to Omaccy. Versions match the `v*` tags that
[.ai/releasing.md](.ai/releasing.md) builds and publishes.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Omaccy follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.2] - unreleased

Dated when the `v0.4.2` tag is cut.

### Changed

- The Mail and Editors pages show each app's real icon instead of one shared
  symbol, so Cursor, Zed, and Thunderbird read at a glance the way the Apps
  page and the desktop agents already do. The icon is read from the app on
  disk, so a choice that is not installed yet keeps the collection's symbol —
  which is now also what marks it as missing before you read the row.

### Fixed

- Cursor picks up every theme, not just some of them. Following the theme
  wrote `window.autoDetectColorScheme: false` only into an editor that already
  had that setting turned on, and Cursor reads a file with no entry of its own
  as permission to follow macOS light/dark instead — so the theme landed in
  `settings.json` and nothing happened on screen, most visibly when the theme
  switch flipped the system appearance at the same time. The setting is now
  written whenever the editor switch is on, which adds one line to
  `settings.json` for anyone who never had it. VS Code was never affected.

## [0.4.1] - 2026-09-10

### Added

- VS Code and Cursor can follow the Omaccy theme, off until
  `scripts/theme.sh editors on` or the switch at the top of Settings → Theme.
  Each palette names the marketplace extension carrying it, which is installed
  when missing, and only the `workbench.colorTheme` line of the editor's
  `settings.json` is rewritten — these files are JSONC, so comments and
  trailing commas survive. The original is copied to `~/.omaccy/backups/`
  before the first edit, and uninstall leaves the editors on whatever theme
  they are on rather than reverting a file the user may have moved on with.
- macOS light and dark can follow the theme too, behind the same kind of
  opt-in: `scripts/theme.sh appearance on` or the second switch on that page.
  Each theme file declares its own `APPEARANCE`, so Catppuccin Latte puts macOS
  in Light and the dark palettes put it back. A theme file without that key
  leaves the appearance alone rather than guessing. The appearance found when
  the switch is first turned on is recorded and restored by uninstall, the way
  the other macOS preferences already are.

### Fixed

- Keep awake no longer ends when SketchyBar restarts. `caffeinate` inherited
  SketchyBar's process group, and `brew services restart sketchybar` — which an
  ordinary theme or font switch performs — made launchd take down that whole
  group. It is now launched in a process group of its own, so a restart leaves
  it running.
- Keep awake resumes if its process is lost anyway. The deadline the user asked
  for is now the stored state and the PID only a cache of the process serving
  it, so each bar tick relaunches `caffeinate` for the time remaining instead of
  quietly reporting keep awake as off. Resume is scoped to the current boot: a
  session survives a restart, but an indefinite one does not come back by itself
  after a reboot.
- The bar no longer shows keep awake as on when it is not. The recorded PID was
  only checked for existence, so a PID reused by an unrelated process — most
  likely across a reboot — read as an active session while the display slept.
  The process is now confirmed to be `caffeinate` before it counts, and before
  uninstall signals it.
- A keep-awake session whose deadline passes is now stopped rather than
  forgotten, so a shortened deadline cannot orphan a `caffeinate` that holds the
  display awake with no recorded PID left to stop it by.
- Setup no longer leaves Hyperkey stopped when it cannot write the app bundle.
  macOS App Management refuses writes into a signed app from a process without
  that permission, and gives a command-line process no prompt — just an error.
  Both install paths stopped the agent and cleared the recorded release before
  discovering that, so a permission problem unrelated to the build left Hyperkey
  dead. They now check first and say which permission to grant, or to move the
  app to the Trash and reinstall.

### Changed

- Setup now deploys every `config/sketchybar/lib/*.sh` by glob instead of by
  name, matching how plugins and themes are already handled, so a library the
  bar sources cannot be left out of an install. Uninstall restores them the same
  way, including libraries added after a machine was set up.
- The palette's Theme page opens with the two switches above, since a theme is
  a choice but how far it reaches is a set of switches, and the questions are
  only worth asking together.
- Theme files carry their editor and appearance mapping alongside the colors:
  `APPEARANCE`, `VSCODE_THEME`, and `VSCODE_EXTENSION` join `GHOSTTY_THEME`. A
  custom palette that omits them keeps working and simply does not reach that
  far.
- Keep-awake state moved to `config/sketchybar/lib/caffeinate-state.sh`, shared
  by the bar plugin and `scripts/uninstall.sh` so both agree on which files hold
  the state and when the recorded PID may be signalled. State now includes
  `~/.omaccy/caffeinate.boot`; state written by earlier versions lacks it and is
  discarded on first run.

## [0.4.0] - 2026-09-08

### Added

- Clipboard history behind Hyper+V, off disk by default. Copies marked with the
  nspasteboard.org concealed convention and copies from known password manager
  apps are skipped; entries stay in memory unless `clipboard_persist` is set,
  and anything copied without a Command+C keystroke expires after 90 seconds.
- Six more SketchyBar themes: Catppuccin Latte, Everforest, GitHub Dark,
  Kanagawa, One Dark, and Solarized Dark.
- Command+1-9 fires one of the first nine palette rows directly; holding Command
  numbers them.

### Changed

- Desktop agents lead the Agents list, ahead of the terminal ones.
- Escape returns to the row you came from rather than the top of the list.
- Update Omaccy moved under Settings, leaving Home at nine collections.

---

Releases before 0.4.1 predate this file. The 0.4.0 entry is reconstructed from
its release commit; for 0.3.0 and earlier, see the annotated `v*` tags and the
commit history.

[0.4.2]: https://github.com/nick-friedrich/omaccy/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/nick-friedrich/omaccy/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/nick-friedrich/omaccy/compare/v0.3.0...v0.4.0
