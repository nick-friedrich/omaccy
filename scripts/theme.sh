#!/usr/bin/env bash
set -euo pipefail

# Switches Omaccy's theme for SketchyBar and the launcher palette. Themes live
# in config/sketchybar/themes and are installed into ~/.omaccy/config by the
# setup scripts; the chosen name is stored in ~/.omaccy/theme.
#
# Usage: bash scripts/theme.sh [list | current | set <name> | editors [on|off]
#                              | appearance [on|off]]

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_PREF="$HOME/.omaccy/theme"
THEMES_REPO="$REPO_ROOT/config/sketchybar/themes"
THEMES_INSTALLED="$HOME/.omaccy/config/sketchybar/themes"
GHOSTTY_CONFIG="$HOME/.omaccy/config/ghostty/config.ghostty"
EDITOR_PREF="$HOME/.omaccy/editor-theme"
APPEARANCE_PREF="$HOME/.omaccy/appearance"
BACKUP_DIR="$HOME/.omaccy/backups"

# write_editor_color_theme lives in its own library so the Swift half of the
# editor theming can be tested against exactly this implementation.
source "$REPO_ROOT/scripts/lib/editor-settings.sh"
# The same arrangement for herdr's [theme] name rewrite.
source "$REPO_ROOT/scripts/lib/herdr-settings.sh"
HERDR_CONFIG="$HOME/.config/herdr/config.toml"
DEFAULT_THEME="catppuccin"

current_theme() {
  local name=""
  [[ -f "$THEME_PREF" ]] && name="$(head -n 1 "$THEME_PREF" | tr -d '[:space:]')"
  [[ -n "$name" ]] || name="$DEFAULT_THEME"
  printf '%s\n' "$name"
}

available_themes() {
  { ls "$THEMES_REPO" 2>/dev/null; ls "$THEMES_INSTALLED" 2>/dev/null; } \
    | sed -n 's/\.sh$//p' | sort -u
}

restart_sketchybar_if_running() {
  command -v brew >/dev/null 2>&1 || return 0
  if brew services list 2>/dev/null | grep -q '^sketchybar[[:space:]].*started'; then
    echo "Restarting SketchyBar to apply the change..."
    brew services restart sketchybar
  fi
}

theme_file_path() {
  local name="$1"
  if [[ -f "$THEMES_INSTALLED/$name.sh" ]]; then
    printf '%s\n' "$THEMES_INSTALLED/$name.sh"
  else
    printf '%s\n' "$THEMES_REPO/$name.sh"
  fi
}

# Ghostty ships built-in themes matching Omaccy's palettes; each theme file
# names its match in GHOSTTY_THEME. Mirrors font.sh's font-family rewrite.
update_ghostty_theme() {
  local name="$1"
  [[ -f "$GHOSTTY_CONFIG" ]] || return 0
  local theme_file
  theme_file="$(theme_file_path "$name")"
  [[ -f "$theme_file" ]] || return 0
  local ghostty_theme
  ghostty_theme="$(source "$theme_file" 2>/dev/null; printf '%s' "${GHOSTTY_THEME:-}")"
  [[ -n "$ghostty_theme" ]] || return 0
  sed -i '' '/^[[:space:]]*theme[[:space:]]*=/d' "$GHOSTTY_CONFIG"
  printf 'theme = %s\n' "$ghostty_theme" >> "$GHOSTTY_CONFIG"
  echo "Ghostty will use the $ghostty_theme theme."
}

# Ghostty does not watch its config file for changes on macOS, and its only
# CLI-level reload command (`+new-window`) is GTK-only. Its bundled scripting
# dictionary (Ghostty.sdef) exposes "perform action" as a native AppleScript
# command though, so this reload needs no Accessibility permission (unlike
# System Events UI scripting) -- just the ordinary Apple Events automation
# already implied by launching Ghostty at all. Guarded by pgrep first because
# `tell application "Ghostty"` launches it if it is not already running.
reload_ghostty_if_running() {
  pgrep -xq ghostty 2>/dev/null || return 0
  echo "Reloading Ghostty's configuration..."
  osascript -e 'tell application "Ghostty" to try
    perform action "reload_config" on terminal 1 of window 1
  end try' >/dev/null 2>&1 || true
}

# VS Code and Cursor read workbench.colorTheme out of their own User
# settings.json and repaint the moment that file changes -- no restart and no
# reload command, unlike Ghostty above. The palette itself lives in a
# marketplace extension though (VS Code ships only a handful, of which
# Solarized Dark is the sole match here), so following a theme can mean
# installing one first: a network round-trip and a change to someone's editor.
# That is why the whole thing waits for an explicit opt-in.
editor_theming_enabled() {
  [[ -f "$EDITOR_PREF" ]] || return 1
  [[ "$(head -n 1 "$EDITOR_PREF" | tr -d '[:space:]')" == "on" ]]
}

# The `code` / `cursor` launchers are on PATH only when the user ran the
# editor's "Install 'code' command in PATH" step; the copy inside the app
# bundle is always present, so fall back to it.
editor_cli() {
  local name="$1" app="$2" path
  if path="$(command -v "$name" 2>/dev/null)"; then
    printf '%s\n' "$path"
    return 0
  fi
  path="/Applications/$app.app/Contents/Resources/app/bin/$name"
  [[ -x "$path" ]] || return 1
  printf '%s\n' "$path"
}

# Installs the theme's extension when it is missing. Failure is reported and
# survived: the color theme is still written, so the editor picks the palette
# up as soon as the extension arrives by any other route.
install_editor_extension() {
  local cli="$1" app="$2" extension="$3"
  [[ -n "$extension" ]] || return 0
  "$cli" --list-extensions 2>/dev/null | grep -qix "$extension" && return 0
  echo "Installing $extension for $app..."
  "$cli" --install-extension "$extension" --force >/dev/null 2>&1 && return 0
  echo "Could not install $extension for $app; $app keeps its current theme until it is." >&2
  return 1
}

# Keeps the untouched original once, the way the setup scripts preserve every
# file they displace.
backup_editor_settings() {
  local settings="$1" app_dir="$2" backup="$BACKUP_DIR/$app_dir-settings.json"
  [[ -f "$backup" ]] && return 0
  mkdir -p "$BACKUP_DIR"
  cp "$settings" "$backup"
}

update_editor_themes() {
  local name="$1"
  editor_theming_enabled || return 0
  local theme_file
  theme_file="$(theme_file_path "$name")"
  [[ -f "$theme_file" ]] || return 0
  local label extension
  label="$(source "$theme_file" 2>/dev/null; printf '%s' "${VSCODE_THEME:-}")"
  extension="$(source "$theme_file" 2>/dev/null; printf '%s' "${VSCODE_EXTENSION:-}")"
  [[ -n "$label" ]] || return 0
  local entry bin app app_dir cli settings
  for entry in "code|Visual Studio Code|Code" "cursor|Cursor|Cursor"; do
    IFS='|' read -r bin app app_dir <<< "$entry"
    cli="$(editor_cli "$bin" "$app")" || continue
    settings="$HOME/Library/Application Support/$app_dir/User/settings.json"
    [[ -f "$settings" ]] || continue
    install_editor_extension "$cli" "$app" "$extension" || true
    backup_editor_settings "$settings" "$app_dir"
    local detected=0
    editor_follows_os_appearance "$settings" && detected=1
    write_editor_theme "$settings" "$label" || continue
    echo "$app will use $label."
    (( detected )) && echo "Turned off $app's window.autoDetectColorScheme, which was overriding the theme."
  done
}

# herdr's config.toml is the user's own file -- herdr writes it during its
# onboarding -- so only `name` under [theme] is rewritten, the original is kept
# once in the backups, and a missing file stays missing. Writing with `>` goes
# through a symlink, so a config linked in from a dotfiles repository stays a
# link. `herdr server reload-config` reaches the running session over its
# socket without disturbing the agents in it, and fails fast when there is no
# session. Mirrors updateHerdrTheme in the launcher's Appearance.swift.
update_herdr_theme() {
  local name="$1" theme_file herdr_theme current updated
  [[ -f "$HERDR_CONFIG" ]] || return 0
  theme_file="$(theme_file_path "$name")"
  [[ -f "$theme_file" ]] || return 0
  herdr_theme="$(source "$theme_file" 2>/dev/null; printf '%s' "${HERDR_THEME:-}")"
  [[ -n "$herdr_theme" ]] || return 0
  # The trailing x keeps command substitution from eating final newlines.
  current="$(cat "$HERDR_CONFIG"; printf x)"
  updated="$(herdr_config_with_theme "$HERDR_CONFIG" "$herdr_theme"; printf x)" || return 0
  [[ "$updated" != "$current" ]] || return 0
  if [[ ! -f "$BACKUP_DIR/herdr-config.toml" ]]; then
    mkdir -p "$BACKUP_DIR"
    printf '%s' "${current%x}" > "$BACKUP_DIR/herdr-config.toml"
  fi
  printf '%s' "${updated%x}" > "$HERDR_CONFIG"
  echo "herdr will use the $herdr_theme theme."
  if command -v herdr >/dev/null 2>&1; then
    herdr server reload-config >/dev/null 2>&1 || true
  fi
}

macos_appearance_enabled() {
  [[ -f "$APPEARANCE_PREF" ]] || return 1
  [[ "$(head -n 1 "$APPEARANCE_PREF" | tr -d '[:space:]')" == "on" ]]
}

# Writing AppleInterfaceStyle with defaults(1) does not take effect live --
# running apps stay on the old appearance until they restart. System Events'
# appearance preferences is the supported route, and like the Ghostty reload
# above it is ordinary Apple Events automation rather than UI scripting, so it
# needs no Accessibility permission -- just a one-time automation prompt.
set_macos_appearance() {
  local appearance="$1" dark="true"
  [[ "$appearance" == "light" ]] && dark="false"
  if ! osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $dark" >/dev/null 2>&1; then
    echo "Could not set the macOS appearance. Allow Omaccy to control System Events under System Settings > Privacy & Security > Automation, then try again." >&2
    return 1
  fi
  echo "macOS switched to $appearance appearance."
}

theme_appearance() {
  local theme_file
  theme_file="$(theme_file_path "$1")"
  [[ -f "$theme_file" ]] || return 1
  # Reset first: APPEARANCE is a plausible name to already have in the
  # environment, and a theme file without one must not inherit it.
  local appearance
  appearance="$(APPEARANCE=""; source "$theme_file" 2>/dev/null; printf '%s' "${APPEARANCE:-}")"
  [[ -n "$appearance" ]] || return 1
  printf '%s\n' "$appearance"
}

# A theme file with no APPEARANCE gets no guess. Defaulting to dark is how a
# light palette came to set macOS to Dark: the installed copy of the theme
# predated the key, and a wrong appearance is worse than none. Custom themes
# opt in by declaring APPEARANCE themselves.
update_macos_appearance() {
  macos_appearance_enabled || return 0
  local appearance
  if ! appearance="$(theme_appearance "$1")"; then
    echo "Note: the installed $1 theme predates the APPEARANCE setting, so macOS keeps its current appearance. Run scripts/update.sh to refresh the installed themes." >&2
    return 0
  fi
  set_macos_appearance "$appearance" || true
}

# The appearance is a macOS preference Omaccy takes over, so the value it
# found is kept the way lib/macos.sh keeps the ones it changes -- uninstall
# puts it back.
record_original_appearance() {
  [[ -f "$APPEARANCE_PREF.original" ]] && return 0
  mkdir -p "$(dirname "$APPEARANCE_PREF")"
  if [[ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" == "Dark" ]]; then
    printf 'dark\n' > "$APPEARANCE_PREF.original"
  else
    printf 'light\n' > "$APPEARANCE_PREF.original"
  fi
}

set_macos_appearance_following() {
  local state="$1"
  mkdir -p "$(dirname "$APPEARANCE_PREF")"
  [[ "$state" == "on" ]] && record_original_appearance
  printf '%s\n' "$state" > "$APPEARANCE_PREF"
  if [[ "$state" == "on" ]]; then
    echo "macOS light/dark will follow the Omaccy theme."
    update_macos_appearance "$(current_theme)"
  else
    echo "macOS keeps whatever appearance you set."
  fi
}

set_editor_theming() {
  local state="$1"
  mkdir -p "$(dirname "$EDITOR_PREF")"
  printf '%s\n' "$state" > "$EDITOR_PREF"
  if [[ "$state" == "on" ]]; then
    echo "VS Code and Cursor will follow the Omaccy theme, installing the theme extension when one is missing."
    update_editor_themes "$(current_theme)"
  else
    echo "VS Code and Cursor will keep their own themes."
  fi
}

set_theme() {
  local name="$1"
  if [[ ! -f "$THEMES_REPO/$name.sh" && ! -f "$THEMES_INSTALLED/$name.sh" ]]; then
    echo "Unknown theme: $name" >&2
    echo "Available themes: $(available_themes | tr '\n' ' ')" >&2
    return 1
  fi
  mkdir -p "$(dirname "$THEME_PREF")"
  printf '%s\n' "$name" > "$THEME_PREF"
  echo "Theme set to $name."
  if [[ ! -f "$THEMES_INSTALLED/$name.sh" && -f "$THEMES_REPO/$name.sh" ]]; then
    echo "Note: run scripts/update.sh to install this theme into ~/.omaccy/config first."
  fi
  update_ghostty_theme "$name"
  reload_ghostty_if_running
  update_macos_appearance "$name"
  update_editor_themes "$name"
  update_herdr_theme "$name"
  restart_sketchybar_if_running
  echo "The launcher palette picks up the theme the next time it opens."
}

list_themes() {
  local current
  current="$(current_theme)"
  local theme
  while IFS= read -r theme; do
    [[ -n "$theme" ]] || continue
    if [[ "$theme" == "$current" ]]; then
      printf '* %s\n' "$theme"
    else
      printf '  %s\n' "$theme"
    fi
  done < <(available_themes)
}

case "${1:-current}" in
  current)
    current_theme
    ;;
  list)
    list_themes
    ;;
  set)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: bash scripts/theme.sh set <name>" >&2
      exit 2
    fi
    set_theme "$2"
    ;;
  appearance)
    case "${2:-status}" in
      on|off)
        set_macos_appearance_following "$2"
        ;;
      status)
        if macos_appearance_enabled; then echo "on"; else echo "off"; fi
        ;;
      *)
        echo "Usage: bash scripts/theme.sh appearance [on | off | status]" >&2
        exit 2
        ;;
    esac
    ;;
  editors)
    case "${2:-status}" in
      on|off)
        set_editor_theming "$2"
        ;;
      status)
        if editor_theming_enabled; then echo "on"; else echo "off"; fi
        ;;
      *)
        echo "Usage: bash scripts/theme.sh editors [on | off | status]" >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "Usage: bash scripts/theme.sh [list | current | set <name> | editors [on|off] | appearance [on|off]]" >&2
    exit 2
    ;;
esac
