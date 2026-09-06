#!/usr/bin/env bash
set -euo pipefail

# Switches Omaccy's UI font across Ghostty, SketchyBar, and the launcher
# palette. The fonts themselves are installed by the setup scripts as the
# font-inter, font-jetbrains-mono, and font-lora Homebrew casks; the choice is
# stored in ~/.omaccy/font. SF Symbols keep SF Pro because they only ship
# there.
#
# Usage: bash scripts/font.sh [list | current | set <font>]

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FONT_PREF="$HOME/.omaccy/font"
GHOSTTY_CONFIG="$HOME/.omaccy/config/ghostty/config.ghostty"
FONTS="inter jetbrains-mono serif"
DEFAULT_FONT="inter"

font_family() {
  case "$1" in
    inter) printf 'Inter' ;;
    jetbrains-mono) printf 'JetBrains Mono' ;;
    serif) printf 'Lora' ;;
    *) return 1 ;;
  esac
}

current_font() {
  local name=""
  [[ -f "$FONT_PREF" ]] && name="$(head -n 1 "$FONT_PREF" | tr -d '[:space:]')"
  [[ -n "$name" ]] || name="$DEFAULT_FONT"
  printf '%s\n' "$name"
}

restart_sketchybar_if_running() {
  command -v brew >/dev/null 2>&1 || return 0
  if brew services list 2>/dev/null | grep -q '^sketchybar[[:space:]].*started'; then
    echo "Restarting SketchyBar to apply the change..."
    brew services restart sketchybar
  fi
}

set_font() {
  local font="$1"
  local family
  family="$(font_family "$font")" || {
    echo "Unknown font: $font (expected one of: $FONTS)" >&2
    return 1
  }

  mkdir -p "$(dirname "$FONT_PREF")"
  printf '%s\n' "$font" > "$FONT_PREF"
  echo "Font set to $font ($family)."

  if [[ -f "$GHOSTTY_CONFIG" ]]; then
    sed -i '' '/^[[:space:]]*font-family[[:space:]]*=/d' "$GHOSTTY_CONFIG"
    printf 'font-family = %s\n' "$family" >> "$GHOSTTY_CONFIG"
    echo "Ghostty will use $family."
  else
    echo "No Omaccy Ghostty config found; only the bar and launcher were changed."
  fi
  restart_sketchybar_if_running
  echo "The launcher palette picks up the font the next time it opens."
}

list_fonts() {
  local current
  current="$(current_font)"
  local font
  for font in $FONTS; do
    if [[ "$font" == "$current" ]]; then
      printf '* %-15s %s\n' "$font" "$(font_family "$font")"
    else
      printf '  %-15s %s\n' "$font" "$(font_family "$font")"
    fi
  done
}

case "${1:-current}" in
  current)
    current_font
    ;;
  list)
    list_fonts
    ;;
  set)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: bash scripts/font.sh set <font>" >&2
      exit 2
    fi
    set_font "$2"
    ;;
  *)
    echo "Usage: bash scripts/font.sh [list | current | set <font>]" >&2
    exit 2
    ;;
esac
