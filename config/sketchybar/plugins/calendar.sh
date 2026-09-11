#!/usr/bin/env bash
set -u

# The month calendar in the clock item's popup. Clicking the date opens it on
# the current month; the rows below the grid step a month back or forward, the
# month name returns to today, and the last row hands over to Calendar.app.
#
# The grid is plain text in JetBrains Mono, which setup installs: a SketchyBar
# label has one color and one font, so the only way to line seven columns up is
# to make every cell the same width. Each day takes four characters and today
# is bracketed -- "[11]" is as wide as " 11 " -- and its week is drawn in the
# accent color, since a label cannot color a single number inside itself.

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CONFIG_DIR/lib/palette.sh"

SKETCHYBAR_BIN="${OMACCY_SKETCHYBAR_BIN:-sketchybar}"
STATE_DIR="${OMACCY_STATE_DIR:-$HOME/.omaccy}"
OFFSET_FILE="$STATE_DIR/calendar-offset"
ITEM_NAME="clock"

bar() {
  "$SKETCHYBAR_BIN" "$@" >/dev/null 2>&1 || true
}

today() {
  printf '%s\n' "${OMACCY_CALENDAR_TODAY:-$(date +%Y-%m-%d)}"
}

# 1 = Monday through 7 = Sunday, the numbering `date +%u` uses. An explicit
# "First day of week" in System Settings wins; without one, macOS goes by the
# region, and so does this -- Monday almost everywhere, Sunday in the handful
# of regions that start there.
first_weekday() {
  if [[ -n "${OMACCY_FIRST_WEEKDAY:-}" ]]; then
    printf '%s\n' "$OMACCY_FIRST_WEEKDAY"
    return
  fi
  local chosen
  chosen="$(defaults read -g AppleFirstWeekday 2>/dev/null |
    awk -F '=' '/gregorian/ { gsub(/[^0-9]/, "", $2); print $2; exit }')"
  if [[ -n "$chosen" ]]; then
    # Apple counts from Sunday = 1.
    if (( chosen == 1 )); then printf '7\n'; else printf '%s\n' $((chosen - 1)); fi
    return
  fi
  case "$(defaults read -g AppleLocale 2>/dev/null)" in
    *_US*|*_CA*|*_JP*|*_BR*|*_MX*|*_IL*|*_PH*|*_KR*|*_TW*) printf '7\n' ;;
    *) printf '1\n' ;;
  esac
}

read_offset() {
  local value=""
  [[ -f "$OFFSET_FILE" ]] && value="$(head -n 1 "$OFFSET_FILE" | tr -d '[:space:]')"
  [[ "$value" =~ ^-?[0-9]+$ ]] || value=0
  printf '%s\n' "$value"
}

write_offset() {
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$1" > "$OFFSET_FILE"
}

# The month `offset` away from today's, as YYYY-MM. The day is pinned to the
# first before stepping, so the 31st plus one month cannot spill into the month
# after next. `-v` without a sign would set the month outright, so 0 stays out.
shown_month() {
  local offset="$1" base
  base="$(today)"
  if (( offset > 0 )); then
    date -j -v1d -v+"${offset}"m -f %Y-%m-%d "$base" +%Y-%m
  elif (( offset < 0 )); then
    date -j -v1d -v"${offset}"m -f %Y-%m-%d "$base" +%Y-%m
  else
    date -j -f %Y-%m-%d "$base" +%Y-%m
  fi
}

render() {
  local month="$1" first days name fw lead now today_month today_day
  first="$(date -j -f %Y-%m-%d "$month-01" +%u)"
  days="$(date -j -v1d -v+1m -v-1d -f %Y-%m-%d "$month-01" +%d)"
  days=$((10#$days))
  # English like the clock beside it, whatever language the system is in.
  name="$(LC_ALL=C date -j -f %Y-%m-%d "$month-01" '+%B %Y')"
  fw="$(first_weekday)"
  lead=$(( (first - fw + 7) % 7 ))
  now="$(today)"
  today_month="${now%-*}"
  today_day=$((10#${now##*-}))

  local names=(Mo Tu We Th Fr Sa Su) header="" i
  for (( i = 0; i < 7; i++ )); do
    header+=" ${names[$(( (fw - 1 + i) % 7 ))]} "
  done

  local rows=() row="" cell day=1 column=0 today_row=-1
  for (( i = 0; i < lead; i++ )); do
    row+="    "
    column=$((column + 1))
  done
  while (( day <= days )); do
    if [[ "$month" == "$today_month" ]] && (( day == today_day )); then
      printf -v cell '[%2d]' "$day"
      today_row=${#rows[@]}
    else
      printf -v cell ' %2d ' "$day"
    fi
    row+="$cell"
    column=$((column + 1))
    day=$((day + 1))
    if (( column == 7 )); then
      rows+=("$row")
      row=""
      column=0
    fi
  done
  [[ -n "$row" ]] && rows+=("$row")

  # One sketchybar call for the whole popup, so the grid never shows half of
  # one month and half of the next. The rows keep their leading blanks; the
  # fixed label width in sketchybarrc is what stops SketchyBar clipping them.
  local args=(--set "$ITEM_NAME.header" label="$name"
              --set "$ITEM_NAME.weekdays" label="$header")
  local color
  for (( i = 0; i < 6; i++ )); do
    if (( i < ${#rows[@]} )); then
      color="$TEXT"
      (( i == today_row )) && color="$ACCENT"
      args+=(--set "$ITEM_NAME.week$((i + 1))" drawing=on label="${rows[$i]}" label.color="$color")
    else
      args+=(--set "$ITEM_NAME.week$((i + 1))" drawing=off)
    fi
  done
  bar "${args[@]}"
}

show() {
  write_offset "$1"
  render "$(shown_month "$1")"
}

action="${1:-click}"
case "$action" in
  click)
    # Always opens on the current month, however far it was paged last time.
    show 0
    bar --set "$ITEM_NAME" popup.drawing=toggle
    ;;
  next)
    show $(( $(read_offset) + 1 ))
    ;;
  prev)
    show $(( $(read_offset) - 1 ))
    ;;
  today)
    show 0
    ;;
  open)
    open -a Calendar >/dev/null 2>&1 || true
    bar --set "$ITEM_NAME" popup.drawing=off
    ;;
  *)
    exit 2
    ;;
esac
