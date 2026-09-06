#!/usr/bin/env bash

# Resolves Omaccy's active theme and exposes its palette variables. Sources the
# theme file matching the name stored in ~/.omaccy/theme (written by
# scripts/theme.sh) and keeps Catppuccin Mocha defaults so a missing, damaged,
# or partial theme file never blanks the bar.

THEMES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../themes" && pwd)"
OMACCY_THEME="catppuccin"

if [[ -f "$HOME/.omaccy/theme" ]]; then
  _omaccy_theme_name="$(head -n 1 "$HOME/.omaccy/theme" | tr -d '[:space:]')"
  if [[ -n "$_omaccy_theme_name" && -f "$THEMES_DIR/$_omaccy_theme_name.sh" ]]; then
    OMACCY_THEME="$_omaccy_theme_name"
  fi
fi
unset _omaccy_theme_name

# Catppuccin Mocha fallbacks; every theme file overrides these.
BAR_BG=0xff11111b
ITEM_BG=0xff1e1e2e
BORDER=0xff45475a
ACCENT=0xff89b4fa
TEXT=0xffcdd6f4
MUTED=0xff7f849c
OK=0xffa6e3a1
DANGER=0xfff38ba8

# A damaged theme file must not spam plugin logs; the defaults above stay in
# effect when sourcing fails.
# shellcheck disable=SC1090,SC1091
source "$THEMES_DIR/$OMACCY_THEME.sh" 2>/dev/null || true
