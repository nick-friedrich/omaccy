#!/usr/bin/env bash
set -u

# The frontmost app's name.
#
# This once also drew a popup of that app's own File, Edit and View, read out
# of the other process over UI scripting, because SketchyBar sits on top of the
# macOS menu bar. The menu bar underneath can simply be clicked through to, so
# the emulation was retired along with the Accessibility access it needed.

SKETCHYBAR_BIN="${OMACCY_SKETCHYBAR_BIN:-sketchybar}"
OSASCRIPT_BIN="${OMACCY_OSASCRIPT_BIN:-/usr/bin/osascript}"
ITEM_NAME="front_app"

bar() {
  "$SKETCHYBAR_BIN" "$@" >/dev/null 2>&1 || true
}

# SketchyBar passes the new app in INFO when it sends front_app_switched; the
# lookup is the fallback for being run by hand or at startup.
app="${INFO:-}"
[[ -n "$app" ]] || app="$("$OSASCRIPT_BIN" -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)"
bar --set "$ITEM_NAME" label="${app:-Desktop}"
