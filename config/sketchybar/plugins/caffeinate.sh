#!/usr/bin/env bash
set -u

STATE_DIR="${OMACCY_STATE_DIR:-$HOME/.omaccy}"
PID_FILE="$STATE_DIR/caffeinate.pid"
END_FILE="$STATE_DIR/caffeinate.ends-at"
CAFFEINATE_BIN="${OMACCY_CAFFEINATE_BIN:-/usr/bin/caffeinate}"
SKETCHYBAR_BIN="${OMACCY_SKETCHYBAR_BIN:-sketchybar}"
ITEM_NAME="caffeinate"

is_active() {
  local pid

  [[ -f "$PID_FILE" ]] || return 1
  pid="$(cat "$PID_FILE" 2>/dev/null)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

clear_state() {
  rm -f "$PID_FILE" "$END_FILE"
}

stop_caffeinate() {
  local pid=""

  if is_active; then
    pid="$(cat "$PID_FILE")"
    kill "$pid" 2>/dev/null || true
  fi
  clear_state
}

start_caffeinate() {
  local duration="${1:-0}"
  local pid
  local now

  [[ "$duration" =~ ^[0-9]+$ ]] || return 1
  stop_caffeinate
  mkdir -p "$STATE_DIR"

  if (( duration > 0 )); then
    "$CAFFEINATE_BIN" -i -t "$duration" >/dev/null 2>&1 &
  else
    "$CAFFEINATE_BIN" -i >/dev/null 2>&1 &
  fi
  pid=$!
  printf '%s\n' "$pid" > "$PID_FILE"

  if (( duration > 0 )); then
    now="$(date +%s)"
    printf '%s\n' "$((now + duration))" > "$END_FILE"
  else
    printf '0\n' > "$END_FILE"
  fi
}

remaining_label() {
  local ends_at
  local now
  local remaining
  local minutes
  local hours

  ends_at="$(cat "$END_FILE" 2>/dev/null || printf '0')"
  [[ "$ends_at" =~ ^[0-9]+$ ]] || ends_at=0
  if (( ends_at == 0 )); then
    printf 'On'
    return
  fi

  now="$(date +%s)"
  remaining=$((ends_at - now))
  if (( remaining <= 0 )); then
    clear_state
    return 1
  fi

  minutes=$(((remaining + 59) / 60))
  if (( minutes < 60 )); then
    printf '%dm' "$minutes"
  else
    hours=$((minutes / 60))
    minutes=$((minutes % 60))
    if (( minutes == 0 )); then
      printf '%dh' "$hours"
    else
      printf '%dh %dm' "$hours" "$minutes"
    fi
  fi
}

update_item() {
  local label

  if is_active && label="$(remaining_label)"; then
    "$SKETCHYBAR_BIN" --set "$ITEM_NAME" \
      icon.color=0xffcdd6f4 \
      label="$label" \
      label.drawing=on \
      background.drawing=on >/dev/null 2>&1 || true
  else
    clear_state
    "$SKETCHYBAR_BIN" --set "$ITEM_NAME" \
      icon.color=0xffcdd6f4 \
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
    elif is_active; then
      stop_caffeinate
    else
      start_caffeinate 0
    fi
    ;;
  start)
    start_caffeinate "${2:-0}"
    close_popup
    ;;
  stop)
    stop_caffeinate
    close_popup
    ;;
  update) ;;
  *) exit 2 ;;
esac

update_item
