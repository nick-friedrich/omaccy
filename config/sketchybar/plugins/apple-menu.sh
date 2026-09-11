#!/usr/bin/env bash
set -u

# The Apple menu. The logo at the left edge of the bar opens a popup with what
# the real Apple menu keeps there -- System Settings and the power actions --
# plus Omaccy's own settings and a way to hand the top of the screen back to
# the macOS menu bar.

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SKETCHYBAR_BIN="${OMACCY_SKETCHYBAR_BIN:-sketchybar}"
OPEN_BIN="${OMACCY_OPEN_BIN:-/usr/bin/open}"
OSASCRIPT_BIN="${OMACCY_OSASCRIPT_BIN:-/usr/bin/osascript}"
PMSET_BIN="${OMACCY_PMSET_BIN:-/usr/bin/pmset}"
MENU_TOGGLE="${OMACCY_MENU_TOGGLE:-$CONFIG_DIR/plugins/menu-toggle.sh}"
ITEM_NAME="native_menu"

bar() {
  "$SKETCHYBAR_BIN" "$@" >/dev/null 2>&1 || true
}

close_popup() {
  bar --set "$ITEM_NAME" popup.drawing=off
}

# Restart, Shut Down and Log Out go to loginwindow as the "show the dialog"
# forms of the power events -- kAEShowRestartDialog ('rrst'),
# kAEShowShutdownDialog ('rsdn') and kAELogOut ('logo') in AERegistry.h -- so
# each asks with the same confirmation the real Apple menu shows, and apps
# still get their say over unsaved work. The palette's System page sends the
# unconfirmed events and asks in its own UI; asking twice from here would be
# worse than either.
loginwindow_event() {
  "$OSASCRIPT_BIN" -e "tell application \"loginwindow\" to «event aevt$1»" >/dev/null 2>&1 || true
}

action="${1:-click}"
case "$action" in
  click)
    bar --set "$ITEM_NAME" popup.drawing=toggle
    ;;
  system-settings)
    close_popup
    "$OPEN_BIN" -b com.apple.systempreferences >/dev/null 2>&1 || true
    ;;
  omaccy-settings)
    # The launcher's own Settings page, through the omaccy:// link the Hyperkey
    # app registers, so the bar never grows a second copy of those settings.
    close_popup
    "$OPEN_BIN" "omaccy://settings" >/dev/null 2>&1 || true
    ;;
  sleep)
    # Immediate, like the real menu's Sleep: nothing is lost by it.
    close_popup
    "$PMSET_BIN" sleepnow >/dev/null 2>&1 || true
    ;;
  restart)
    close_popup
    loginwindow_event rrst
    ;;
  shutdown)
    close_popup
    loginwindow_event rsdn
    ;;
  logout)
    close_popup
    loginwindow_event logo
    ;;
  hide-bar)
    # The same as Hyper+M, which is also how the bar comes back.
    close_popup
    "$MENU_TOGGLE" >/dev/null 2>&1 || true
    ;;
  *)
    exit 2
    ;;
esac
