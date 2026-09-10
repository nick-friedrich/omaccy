#!/usr/bin/env bash
set -u

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CONFIG_DIR/lib/palette.sh"
source "$CONFIG_DIR/lib/caffeinate-state.sh"

SKETCHYBAR_BIN="${OMACCY_SKETCHYBAR_BIN:-sketchybar}"
ITEM_NAME="caffeinate"

# Every invocation ends here, including the periodic tick, so a caffeinate that
# was killed with the SketchyBar service comes back rather than the bar quietly
# reporting keep-awake as off.
update_item() {
  local remaining

  if remaining="$(caffeinate_remaining)" && caffeinate_ensure_running; then
    "$SKETCHYBAR_BIN" --set "$ITEM_NAME" \
      icon.color="$TEXT" \
      label="$(caffeinate_label "$remaining")" \
      label.drawing=on \
      background.drawing=on >/dev/null 2>&1 || true
  else
    caffeinate_clear_state
    "$SKETCHYBAR_BIN" --set "$ITEM_NAME" \
      icon.color="$TEXT" \
      label.drawing=off \
      background.drawing=off >/dev/null 2>&1 || true
  fi
}

close_popup() {
  "$SKETCHYBAR_BIN" --set "$ITEM_NAME" popup.drawing=off >/dev/null 2>&1 || true
}

action="${1:-update}"
case "$action" in
  click)
    if [[ "${BUTTON:-left}" == "right" ]]; then
      "$SKETCHYBAR_BIN" --set "$ITEM_NAME" popup.drawing=toggle >/dev/null 2>&1 || true
    elif caffeinate_remaining >/dev/null; then
      caffeinate_stop
    else
      caffeinate_start 0
    fi
    ;;
  start)
    caffeinate_start "${2:-0}"
    close_popup
    ;;
  stop)
    caffeinate_stop
    close_popup
    ;;
  update) ;;
  *) exit 2 ;;
esac

update_item
