#!/usr/bin/env bash
set -euo pipefail

# Switches Omaccy's theme for SketchyBar and the launcher palette. Themes live
# in config/sketchybar/themes and are installed into ~/.omaccy/config by the
# setup scripts; the chosen name is stored in ~/.omaccy/theme.
#
# Usage: bash scripts/theme.sh [list | current | set <name>]

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_PREF="$HOME/.omaccy/theme"
THEMES_REPO="$REPO_ROOT/config/sketchybar/themes"
THEMES_INSTALLED="$HOME/.omaccy/config/sketchybar/themes"
GHOSTTY_CONFIG="$HOME/.omaccy/config/ghostty/config.ghostty"
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
  *)
    echo "Usage: bash scripts/theme.sh [list | current | set <name>]" >&2
    exit 2
    ;;
esac
