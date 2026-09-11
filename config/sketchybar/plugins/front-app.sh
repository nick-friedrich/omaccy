#!/usr/bin/env bash
set -u

# The frontmost app's name, and a popup of its menus. SketchyBar sits over the
# macOS menu bar, so an app's File, Edit, View and the rest are otherwise out
# of reach without Hyper+M. Clicking the name lists the app's menu titles, and
# choosing one opens that menu -- drawn by macOS, as if its title had been
# clicked in the real menu bar.
#
# Reading and opening another app's menus is UI scripting, which macOS allows
# only once SketchyBar has Accessibility access. Until then the popup holds a
# single row that opens that page of Privacy & Security.

SKETCHYBAR_BIN="${OMACCY_SKETCHYBAR_BIN:-sketchybar}"
OPEN_BIN="${OMACCY_OPEN_BIN:-/usr/bin/open}"
OSASCRIPT_BIN="${OMACCY_OSASCRIPT_BIN:-/usr/bin/osascript}"
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/front-app.sh"
ITEM_NAME="front_app"
# sketchybarrc adds this many hidden popup rows; keep the two in step.
MENU_ROWS=16
ACCESSIBILITY_PANE="x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

bar() {
  "$SKETCHYBAR_BIN" "$@" >/dev/null 2>&1 || true
}

close_popup() {
  bar --set "$ITEM_NAME" popup.drawing=off
}

is_number() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
}

# Prints the frontmost app's pid, then the title of every menu in its menu bar,
# one per line, starting with the Apple menu.
read_menus() {
  "$OSASCRIPT_BIN" 2>/dev/null <<'APPLESCRIPT'
tell application "System Events"
  set frontApp to first application process whose frontmost is true
  set appId to unix id of frontApp
  set titles to name of every menu bar item of menu bar 1 of frontApp
end tell
set AppleScript's text item delimiters to linefeed
return (appId as text) & linefeed & (titles as text)
APPLESCRIPT
}

# Each row carries the pid and the menu's position in the bar rather than its
# title, so choosing it opens the menu of the app the popup was filled for,
# and titles never have to survive a trip through a shell command.
fill_menus() {
  local output pid="" title index=0 row=0
  local args=()

  if output="$(read_menus)"; then
    {
      read -r pid
      while IFS= read -r title; do
        index=$((index + 1))
        # The Apple menu has its own item at the left of the bar.
        [[ $index -eq 1 ]] && continue
        [[ -z "$title" || "$title" == "missing value" ]] && continue
        [[ $row -ge $MENU_ROWS ]] && break
        row=$((row + 1))
        args+=(--set "$ITEM_NAME.menu.$row" label="$title" drawing=on
          click_script="'$PLUGIN' open $pid $index")
      done
    } <<< "$output"
  fi

  if ! is_number "$pid" || [[ $row -eq 0 ]]; then
    row=1
    args=(--set "$ITEM_NAME.menu.1" label="Allow SketchyBar in Accessibility…" drawing=on
      click_script="'$PLUGIN' accessibility")
  fi

  while [[ $row -lt $MENU_ROWS ]]; do
    row=$((row + 1))
    args+=(--set "$ITEM_NAME.menu.$row" drawing=off)
  done

  bar "${args[@]}"
}

action="${1:-update}"
case "$action" in
  update)
    # A menu list belongs to the app it was read from, so switching apps
    # closes it rather than leaving the last app's menus on screen.
    app="${INFO:-}"
    [[ -n "$app" ]] || app="$("$OSASCRIPT_BIN" -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)"
    bar --set "$ITEM_NAME" label="${app:-Desktop}" popup.drawing=off
    ;;
  click)
    # Either button: the name had no click of its own before this.
    fill_menus
    bar --set "$ITEM_NAME" popup.drawing=toggle
    ;;
  open)
    pid="${2:-}"
    index="${3:-}"
    is_number "$pid" && is_number "$index" || exit 2
    close_popup
    # Pressing a menu title does not return until the menu closes again, so
    # the script does not wait for System Events to answer.
    "$OSASCRIPT_BIN" -e "ignoring application responses
tell application \"System Events\" to click menu bar item $index of menu bar 1 of (first application process whose unix id is $pid)
end ignoring" >/dev/null 2>&1 || true
    ;;
  accessibility)
    close_popup
    "$OPEN_BIN" "$ACCESSIBILITY_PANE" >/dev/null 2>&1 || true
    ;;
  *)
    exit 2
    ;;
esac
