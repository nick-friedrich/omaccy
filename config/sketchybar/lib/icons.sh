#!/usr/bin/env bash

# SF Symbols glyphs live only in SF Pro, which macOS does not ship as an
# installable font family; setup adds it to ~/Library/Fonts without sudo. That
# install can be declined, fail, or run offline, and a bar drawing nothing at
# all reads as broken rather than as a missing font -- so every symbol here has
# a plain-Unicode twin that any installed font can draw. Sourced by sketchybarrc
# and by the plugins that choose their own icons.

sf_pro_available() {
  local dir
  for dir in "$HOME/Library/Fonts" /Library/Fonts /System/Library/Fonts; do
    [[ -f "$dir/SF-Pro.ttf" ]] && return 0
  done
  return 1
}

if sf_pro_available; then
  # Empty means "compose from the chosen text font", which sketchybarrc does.
  ICON_FONT_FAMILY="SF Pro"
  ICON_CLOCK="􀐫"
  ICON_TILING="􀓗"
  ICON_CAFFEINATE="􀸙"
  ICON_BATTERY="􀛨"
  ICON_BATTERY_CHARGING="􀢋"
  ICON_BATTERY_10="􀛪"
  ICON_BATTERY_30="􀛩"
  ICON_BATTERY_60="􀺶"
  ICON_BATTERY_85="􀺸"
else
  ICON_FONT_FAMILY=""
  ICON_CLOCK="◷"
  ICON_TILING="▦"
  ICON_CAFFEINATE="☾"
  ICON_BATTERY="▰"
  ICON_BATTERY_CHARGING="⚡"
  ICON_BATTERY_10="▱"
  ICON_BATTERY_30="▱"
  ICON_BATTERY_60="▰"
  ICON_BATTERY_85="▰"
fi
